-- Live sport reports are precise observations, not another strain algorithm. The
-- training calculation may use only bounded adjacent intervals in one continuity.
create table public.sport_heart_rate_samples (
  user_id uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  session_id uuid not null,
  continuity_id uuid not null,
  observed_at timestamptz not null,
  heart_rate smallint not null check (heart_rate between 1 and 250),
  sport_mode integer check (sport_mode between 0 and 65535),
  sampled_tz text not null,
  source text not null default 'live_sport' check (source = 'live_sport'),
  received_at timestamptz not null default now(),
  primary key(user_id,id),
  check (isfinite(observed_at) and observed_at >= '2000-01-01'::timestamptz)
);
create index sport_heart_rate_samples_user_time
  on public.sport_heart_rate_samples(user_id,observed_at);
create index sport_heart_rate_samples_continuity
  on public.sport_heart_rate_samples(user_id,session_id,continuity_id,observed_at);
comment on table public.sport_heart_rate_samples is
  'Live HR receipts persisted by the app. Only adjacent observations within the same session/continuity and at most 15 seconds apart establish observed training intervals; no session-wide or gap extrapolation.';
comment on column public.sport_heart_rate_samples.sport_mode is
  'App-started sport mode; null when joining a workout whose actual mode was not verified.';

alter table public.sport_heart_rate_samples enable row level security;
revoke all on public.sport_heart_rate_samples from anon,authenticated;
grant select,insert on public.sport_heart_rate_samples to authenticated;
grant all on public.sport_heart_rate_samples to service_role;
create policy sport_evidence_read on public.sport_heart_rate_samples for select to authenticated
  using(user_id=(select auth.uid()));
create policy sport_evidence_insert on public.sport_heart_rate_samples for insert to authenticated
  with check(user_id=(select auth.uid())
    and observed_at <= now()+interval '5 minutes'
    and exists(select 1 from pg_catalog.pg_timezone_names z where z.name=sampled_tz)
    and exists(select 1 from public.profiles p where p.user_id=(select auth.uid())
      and p.deletion_requested_at is null)
    and (select choice from public.consents c where c.user_id=(select auth.uid())
      order by c.decided_at desc,c.id desc limit 1)='granted');

-- One statement invalidates once per owner rather than once per live report. The
-- 15-second lookbehind includes an interval straddling the 04:00 user-day boundary.
-- This private trigger needs privilege only to update the existing internal work queue.
create function nb.on_sport_heart_rate_insert() returns trigger
language plpgsql security definer set search_path='' as $$
declare changed record;
begin
  for changed in
    select s.user_id,min(least(
      nb.user_day_of(s.observed_at-interval '15 seconds',p.timezone),
      nb.user_day_of(s.observed_at-interval '15 seconds',s.sampled_tz))) as user_day
    from inserted_sport_samples s join public.profiles p using(user_id)
    group by s.user_id
  loop
    perform nb.invalidate_calculation(changed.user_id,changed.user_day);
  end loop;
  return null;
end $$;
revoke all on function nb.on_sport_heart_rate_insert() from public,anon,authenticated;
create trigger sport_heart_rate_inserted after insert on public.sport_heart_rate_samples
  referencing new table as inserted_sport_samples for each statement
  execute function nb.on_sport_heart_rate_insert();

-- RLS remains active in this invoker RPC. Identity is derived from auth.uid(), never
-- supplied by the client. Atomic validation makes conflicting replays fail instead
-- of acknowledging a different sample under the same operation id.
create function public.ingest_sport_heart_rate(p_samples jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare owner uuid:=(select auth.uid()); n integer; acknowledged jsonb;
begin
  if owner is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  perform 1 from public.profiles where user_id=owner and deletion_requested_at is null for share;
  if not found then raise exception 'ACCOUNT_UNAVAILABLE' using errcode='42501'; end if;
  if (select choice from public.consents where user_id=owner order by decided_at desc,id desc limit 1)
    is distinct from 'granted' then raise exception 'CONSENT_REQUIRED' using errcode='42501'; end if;
  if p_samples is null or jsonb_typeof(p_samples)<>'array'
    or jsonb_array_length(p_samples) not between 1 and 300
    or octet_length(p_samples::text)>300000 then
    raise exception 'INVALID_SPORT_BATCH' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_to_recordset(p_samples) as s(
      id uuid,session_id uuid,continuity_id uuid,observed_at timestamptz,
      heart_rate integer,sport_mode integer,sampled_tz text)
    where s.id is null or s.session_id is null or s.continuity_id is null
      or s.observed_at is null or not isfinite(s.observed_at)
      or s.observed_at < '2000-01-01'::timestamptz or s.observed_at>now()+interval '5 minutes'
      or s.heart_rate is null or s.heart_rate not between 1 and 250
      or s.sport_mode not between 0 and 65535
      or s.sampled_tz is null or not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=s.sampled_tz))
    then raise exception 'INVALID_SPORT_SAMPLE' using errcode='22023'; end if;

  insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,
    observed_at,heart_rate,sport_mode,sampled_tz)
  select owner,s.id,s.session_id,s.continuity_id,s.observed_at,s.heart_rate,s.sport_mode,s.sampled_tz
  from jsonb_to_recordset(p_samples) as s(id uuid,session_id uuid,continuity_id uuid,
    observed_at timestamptz,heart_rate smallint,sport_mode integer,sampled_tz text)
  on conflict(user_id,id) do nothing;
  get diagnostics n=row_count;

  if exists(select 1 from jsonb_to_recordset(p_samples) as s(id uuid,session_id uuid,
      continuity_id uuid,observed_at timestamptz,heart_rate smallint,sport_mode integer,sampled_tz text)
    left join public.sport_heart_rate_samples stored on stored.user_id=owner and stored.id=s.id
    where stored.id is null or (stored.session_id,stored.continuity_id,stored.observed_at,
      stored.heart_rate,stored.sport_mode,stored.sampled_tz) is distinct from
      (s.session_id,s.continuity_id,s.observed_at,s.heart_rate,s.sport_mode,s.sampled_tz))
    then raise exception 'SPORT_OPERATION_CONFLICT' using errcode='23505'; end if;
  select jsonb_agg(distinct s->>'id') into acknowledged from jsonb_array_elements(p_samples) s;
  return jsonb_build_object('inserted',n,'acknowledged_ids',acknowledged);
end $$;
revoke all on function public.ingest_sport_heart_rate(jsonb) from public,anon;
grant execute on function public.ingest_sport_heart_rate(jsonb) to authenticated;

-- Keep the existing compatibility export/delete bodies; add only the new domain.
do $$ declare definition text; begin
  definition:=pg_get_functiondef('public.export_all()'::regprocedure);
  if position('''balance_checks''' in definition)=0 then raise exception 'export_all anchor missing'; end if;
  definition:=replace(definition,'''balance_checks'',',
    '''sport_heart_rate_samples'', (select coalesce(jsonb_agg(to_jsonb(s) order by s.observed_at,s.id), ''[]''::jsonb) from public.sport_heart_rate_samples s where s.user_id=(select auth.uid())), ''balance_checks'',');
  execute definition;
  definition:=pg_get_functiondef('public.account_delete(text)'::regprocedure);
  if position('delete from public.balance_checks' in definition)=0 then raise exception 'account_delete anchor missing'; end if;
  definition:=replace(definition,'delete from public.balance_checks',
    'delete from public.sport_heart_rate_samples where user_id = v_user; delete from public.balance_checks');
  execute definition;
end $$;
