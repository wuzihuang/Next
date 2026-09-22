-- A declared workout window owns existing observations; it is never a sensor sample.
create table public.manual_sport_sessions (
 user_id uuid not null references auth.users(id) on delete cascade,
 id uuid not null,
 user_day date not null,
 started_at timestamptz not null,
 ended_at timestamptz not null,
 sport_mode integer check(sport_mode between 0 and 65535),
 timezone text not null,
 request_payload jsonb not null,
 created_at timestamptz not null default now(),
 primary key(user_id,id),
 check(isfinite(started_at) and isfinite(ended_at) and ended_at>started_at
   and ended_at-started_at<=interval '24 hours')
);
create index manual_sport_sessions_window on public.manual_sport_sessions(user_id,started_at,ended_at);
alter table public.manual_sport_sessions enable row level security;
revoke all on public.manual_sport_sessions from public,anon,authenticated;
grant select on public.manual_sport_sessions to authenticated;
grant all on public.manual_sport_sessions to service_role;
create policy manual_sport_sessions_read on public.manual_sport_sessions for select to authenticated
 using(user_id=(select auth.uid()));
create trigger calculation_fact_changed after insert or update or delete on public.manual_sport_sessions
 for each row execute function nb.on_calculation_fact();

alter function nb.training_ledger_uncached(uuid,date) rename to training_observed_ledger;
create function nb.training_ledger_uncached(p_user uuid,p_user_day date)
returns table(ts timestamptz,starts_at timestamptz,ends_at timestamptz,
 session_id uuid,sport_mode integer,heart smallint,z smallint,raw numeric,
 observed_seconds numeric,hr_seconds numeric,movement_seconds numeric,sustained boolean)
language sql stable set search_path='' as $$
 with original as materialized(select * from nb.training_observed_ledger(p_user,p_user_day)),
 split as (
  select o.*,b.a,lead(b.a) over(partition by o.starts_at,o.ends_at order by b.a) b
  from original o cross join lateral (
   select o.starts_at a union select o.ends_at
   union select greatest(m.started_at,o.starts_at) from public.manual_sport_sessions m
    where m.user_id=p_user and m.started_at<o.ends_at and m.ended_at>o.starts_at
   union select least(m.ended_at,o.ends_at) from public.manual_sport_sessions m
    where m.user_id=p_user and m.started_at<o.ends_at and m.ended_at>o.starts_at
  ) b
 ), owned as (
  select s.*,m.id manual_id,m.sport_mode manual_mode,
   extract(epoch from(s.b-s.a))/extract(epoch from(s.ends_at-s.starts_at)) fraction
  from split s left join lateral (
   select m.* from public.manual_sport_sessions m where m.user_id=p_user
    and m.started_at<=s.a and m.ended_at>=s.b order by m.created_at,m.id limit 1
  ) m on s.session_id is null where s.b>s.a
 )
 select ts,a,b,coalesce(session_id,manual_id),coalesce(sport_mode,manual_mode),heart,z,
  raw*fraction*case when manual_id is not null and not sustained then 4 else 1 end,
  observed_seconds*fraction,hr_seconds*fraction,movement_seconds*fraction,sustained
 from owned;
$$;
revoke all on function nb.training_ledger_uncached(uuid,date),nb.training_observed_ledger(uuid,date)
 from public,anon,authenticated;

-- Include empty declarations as missing, so saving a workout never claims invented
-- HR or load. New raw observations automatically fill its evidence on normal replay.
create or replace function nb.training_sessions(p_user uuid,p_user_day date)
returns jsonb language sql stable set search_path='' as $$
 with bounds as (
  select b.* from nb.calculation_profile(p_user,p_user_day) p
   cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b
 ), contributions as (
  select session_id,max(sport_mode) sport_mode,min(starts_at) started_at,max(ends_at) ended_at,
   sum(observed_seconds) observed_seconds,sum(hr_seconds) hr_seconds,
   sum(raw) raw_load,sum(load_delta) load_delta,sum(displayed_delta) displayed_delta,
   min(load_before) load_before,max(load_after) load_after
  from nb.training_contributions(p_user,p_user_day) where session_id is not null group by session_id
 ), declarations as (
  select m.* ,greatest(m.started_at,b.starts_at) day_start,least(m.ended_at,b.ends_at) day_end
  from public.manual_sport_sessions m cross join bounds b where m.user_id=p_user
   and m.started_at<b.ends_at and m.ended_at>b.starts_at
 ), sessions as (
  select coalesce(c.session_id,m.id) session_id,coalesce(m.sport_mode,c.sport_mode) sport_mode,
   coalesce(m.day_start,c.started_at) started_at,coalesce(m.day_end,c.ended_at) ended_at,
   coalesce(c.observed_seconds,0) observed_seconds,coalesce(c.hr_seconds,0) hr_seconds,
   c.raw_load,case when c.raw_load is not null then c.load_delta end load_delta,
   case when c.raw_load is not null then c.displayed_delta end displayed_delta,c.load_before,c.load_after,
   case when m.id is null then 'device' else 'manual' end source,
   case when coalesce(c.observed_seconds,0)=0 then 'missing'
    when c.observed_seconds<extract(epoch from(coalesce(m.day_end,c.ended_at)-coalesce(m.day_start,c.started_at)))
    then 'partial' else 'complete' end data_status
  from contributions c full join declarations m on m.id=c.session_id
 ) select coalesce(jsonb_agg(to_jsonb(s) order by s.started_at,s.session_id),'[]'::jsonb) from sessions s;
$$;

-- The private command needs settlement privileges; the exposed wrapper is invoker.
create schema if not exists health_commands;
revoke all on schema health_commands from public,anon;
grant usage on schema health_commands to authenticated;
create function health_commands.log_sport_session(p_user_day date,p_start text,p_end text,
 p_mode integer,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare owner uuid:=auth.uid(); zone text; v_start timestamptz; v_end timestamptz;
 local_start timestamp; local_end timestamp; previous public.manual_sport_sessions%rowtype;
 payload jsonb; receipt jsonb; replay boolean:=false; budget jsonb;
begin
 if owner is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 select timezone into zone from public.profiles where user_id=owner and deletion_requested_at is null for share;
 if zone is null then raise exception 'ACCOUNT_UNAVAILABLE' using errcode='42501'; end if;
 if (select choice from public.consents where user_id=owner order by decided_at desc,id desc limit 1)
  is distinct from 'granted' then raise exception 'CONSENT_WITHDRAWN' using errcode='42501'; end if;
 if p_request_id is null or p_user_day is null or not isfinite(p_user_day)
  or p_mode not between 0 and 65535
  or coalesce(p_start,'') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
  or coalesce(p_end,'') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
  or p_start=p_end then raise exception 'INVALID_SPORT_WINDOW' using errcode='22023'; end if;
 payload:=jsonb_build_object('user_day',p_user_day,'start',p_start,'end',p_end,'mode',p_mode);
 perform pg_advisory_xact_lock(hashtextextended(owner::text||':manual-sport',0));
 select * into previous from public.manual_sport_sessions where user_id=owner and id=p_request_id;
 if found then
  if previous.request_payload<>payload then raise exception 'SPORT_OPERATION_CONFLICT' using errcode='23505'; end if;
  replay:=true; v_start:=previous.started_at; v_end:=previous.ended_at; zone:=previous.timezone;
 else
  if p_user_day<nb.user_day_of(nb.calculation_clock(),zone)-30
   then raise exception 'SPORT_TOO_OLD' using errcode='22023'; end if;
  if p_user_day>nb.user_day_of(nb.calculation_clock(),zone)
   then raise exception 'SPORT_IN_FUTURE' using errcode='22023'; end if;
  local_start:=p_user_day+p_start::time;
  local_end:=(p_user_day+case when p_end::time<p_start::time then 1 else 0 end)+p_end::time;
  v_start:=local_start at time zone zone; v_end:=local_end at time zone zone;
  -- Reject nonexistent spring-forward times instead of moving the requested clock.
  if v_start at time zone zone<>local_start or v_end at time zone zone<>local_end
   or v_end<=v_start or v_end-v_start>interval '24 hours'
   then raise exception 'INVALID_SPORT_WINDOW' using errcode='22023'; end if;
  if v_end>nb.calculation_clock() then raise exception 'SPORT_IN_FUTURE' using errcode='22023'; end if;
  if exists(select 1 from public.sport_heart_rate_samples where user_id=owner and session_id=p_request_id)
   or exists(select 1 from public.sport_energy_samples where user_id=owner and session_id=p_request_id)
   then raise exception 'SPORT_OPERATION_CONFLICT' using errcode='23505'; end if;
  if exists(select 1 from public.manual_sport_sessions m where m.user_id=owner
   and m.started_at<v_end and m.ended_at>v_start)
   then raise exception 'SPORT_WINDOW_OVERLAP' using errcode='22023'; end if;
  if exists(select 1
   from generate_series(p_user_day,nb.user_day_of(v_end-interval '1 microsecond',zone),interval '1 day') d
   cross join lateral nb.training_observed_ledger(owner,d::date) l
   where l.session_id is not null and l.starts_at<v_end and l.ends_at>v_start)
   then raise exception 'SPORT_WINDOW_OVERLAP' using errcode='22023'; end if;
  budget:=nb.consume_request_budget(owner,'sport-log');
  if not (budget->>'allowed')::boolean then raise exception 'RATE_LIMITED' using errcode='54000'; end if;
  insert into public.manual_sport_sessions(user_id,id,user_day,started_at,ended_at,sport_mode,timezone,request_payload)
   values(owner,p_request_id,p_user_day,v_start,v_end,p_mode,zone,payload);
 end if;
 -- Return evidence from the same ledger that normal ordered settlement publishes.
 -- The app's existing settle request publishes the day and all dependent days.
 select jsonb_build_object('observed_seconds',coalesce(sum((s->>'observed_seconds')::numeric),0),
  'hr_seconds',coalesce(sum((s->>'hr_seconds')::numeric),0),
  'load_delta',sum((s->>'load_delta')::numeric),'displayed_delta',sum((s->>'displayed_delta')::numeric))
 into receipt from generate_series(p_user_day,nb.user_day_of(v_end-interval '1 microsecond',zone),interval '1 day') d
 cross join lateral jsonb_array_elements(nb.training_sessions(owner,d::date)) s
 where s->>'session_id'=p_request_id::text;
 return receipt||jsonb_build_object('session_id',p_request_id,'user_day',p_user_day,'started_at',v_start,
  'ended_at',v_end,'sport_mode',p_mode,'source','manual','replay',replay,
  'data_status',case when (receipt->>'observed_seconds')::numeric=0 then 'missing'
   when (receipt->>'observed_seconds')::numeric<extract(epoch from(v_end-v_start)) then 'partial' else 'complete' end);
end $$;
revoke all on function health_commands.log_sport_session(date,text,text,integer,uuid) from public,anon;
grant execute on function health_commands.log_sport_session(date,text,text,integer,uuid) to authenticated;
create function public.log_sport_session(p_user_day date,p_start text,p_end text,p_mode integer,p_request_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select health_commands.log_sport_session(p_user_day,p_start,p_end,p_mode,p_request_id);
$$;
revoke all on function public.log_sport_session(date,text,text,integer,uuid) from public,anon;
grant execute on function public.log_sport_session(date,text,text,integer,uuid) to authenticated;

do $$ declare definition text; begin
 select pg_get_constraintdef(oid) into definition from pg_constraint
  where conrelid='nb.request_budgets'::regclass and conname='request_budgets_endpoint_check';
 execute 'alter table nb.request_budgets drop constraint request_budgets_endpoint_check';
 execute 'alter table nb.request_budgets add constraint request_budgets_endpoint_check '
  ||replace(definition,'''sleep-correction''','''sport-log'', ''sleep-correction''');
 definition:=pg_get_functiondef('nb.consume_request_budget(uuid,text)'::regprocedure);
 execute replace(definition,'when ''archive-data'' then 6','when ''sport-log'' then 10 when ''archive-data'' then 6');
 definition:=pg_get_functiondef('public.export_all()'::regprocedure);
 if position('''balance_checks''' in definition)=0 then raise exception 'export_all anchor missing'; end if;
 execute replace(definition,'''balance_checks'',',
  '''manual_sport_sessions'', (select coalesce(jsonb_agg(to_jsonb(s) order by s.started_at,s.id), ''[]''::jsonb) from public.manual_sport_sessions s where s.user_id=(select auth.uid())), ''balance_checks'',');
 definition:=pg_get_functiondef('nb.account_delete_legacy_oxygen(text)'::regprocedure);
 if position('delete from public.balance_checks' in definition)=0 then raise exception 'account_delete anchor missing'; end if;
 execute replace(definition,'delete from public.balance_checks',
  'delete from public.manual_sport_sessions where user_id=v_user; delete from public.balance_checks');
end $$;
