-- Strength modes use conservative session-average MET values from the same 2024
-- Compendium mapping as the live client. Ambiguous sport modes remain outside this
-- branch until they have an explicit activity choice.
create or replace function nb.strength_met(p_sport_mode integer) returns numeric
language sql immutable set search_path='' as $$
 select case p_sport_mode
   when 25 then 3.5 -- weightlifting, general multi-exercise
   when 29 then 5.0 -- squat training, slow or explosive effort
   when 46 then 3.0 -- body-weight resistance, general
   when 47 then 3.5 -- dumbbell, general multi-exercise
 end;
$$;

-- Running-state evidence is separate from optical HR evidence: a valid strength
-- interval can exist while the wrist cannot obtain a beat during a grip-heavy set.
create table public.sport_energy_samples (
 user_id uuid not null references auth.users(id) on delete cascade,
 id uuid not null,
 session_id uuid not null,
 continuity_id uuid not null,
 observed_at timestamptz not null,
 sport_mode integer not null check(sport_mode in(25,29,46,47)),
 sampled_tz text not null,
 source text not null default 'live_sport' check(source='live_sport'),
 received_at timestamptz not null default now(),
 primary key(user_id,id),
 check(isfinite(observed_at) and observed_at>='2000-01-01'::timestamptz)
);
create index sport_energy_samples_user_time
 on public.sport_energy_samples(user_id,observed_at);
create index sport_energy_samples_continuity
 on public.sport_energy_samples(user_id,session_id,continuity_id,observed_at);
comment on table public.sport_energy_samples is
 'Running-state receipts for explicit strength modes. Adjacent reports within one continuity and at most 15 seconds apart establish energy intervals; rows contain facts, never client-calculated calories.';

alter table public.sport_energy_samples enable row level security;
revoke all on public.sport_energy_samples from anon,authenticated;
grant select,insert on public.sport_energy_samples to authenticated;
grant all on public.sport_energy_samples to service_role;
create policy sport_energy_read on public.sport_energy_samples for select to authenticated
 using(user_id=(select auth.uid()));
create policy sport_energy_insert on public.sport_energy_samples for insert to authenticated
 with check(user_id=(select auth.uid())
  and observed_at<=now()+interval '5 minutes'
  and exists(select 1 from pg_catalog.pg_timezone_names z where z.name=sampled_tz)
  and exists(select 1 from public.profiles p where p.user_id=(select auth.uid())
   and p.deletion_requested_at is null)
  and (select choice from public.consents c where c.user_id=(select auth.uid())
   order by c.decided_at desc,c.id desc limit 1)='granted');

-- Reuse the statement-level invalidation function: both evidence tables expose
-- the user/time/time-zone fields it reads from inserted_sport_samples.
create trigger sport_energy_inserted after insert on public.sport_energy_samples
 referencing new table as inserted_sport_samples for each statement
 execute function nb.on_sport_heart_rate_insert();

create function public.ingest_sport_energy(p_samples jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare owner uuid:=(select auth.uid()); n integer; acknowledged jsonb;
begin
 if owner is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 perform 1 from public.profiles where user_id=owner and deletion_requested_at is null for share;
 if not found then raise exception 'ACCOUNT_UNAVAILABLE' using errcode='42501'; end if;
 if (select choice from public.consents where user_id=owner
   order by decided_at desc,id desc limit 1) is distinct from 'granted' then
  raise exception 'CONSENT_REQUIRED' using errcode='42501';
 end if;
 if p_samples is null or jsonb_typeof(p_samples)<>'array'
   or jsonb_array_length(p_samples) not between 1 and 300
   or octet_length(p_samples::text)>300000 then
  raise exception 'INVALID_SPORT_ENERGY_BATCH' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_to_recordset(p_samples) as s(
    id uuid,session_id uuid,continuity_id uuid,observed_at timestamptz,
    sport_mode integer,sampled_tz text)
   where s.id is null or s.session_id is null or s.continuity_id is null
    or s.observed_at is null or not isfinite(s.observed_at)
    or s.observed_at<'2000-01-01'::timestamptz
    or s.observed_at>now()+interval '5 minutes'
    or s.sport_mode is null or s.sport_mode not in(25,29,46,47)
    or s.sampled_tz is null
    or not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=s.sampled_tz)) then
  raise exception 'INVALID_SPORT_ENERGY_SAMPLE' using errcode='22023';
 end if;
 insert into public.sport_energy_samples(user_id,id,session_id,continuity_id,
  observed_at,sport_mode,sampled_tz)
 select owner,s.id,s.session_id,s.continuity_id,s.observed_at,s.sport_mode,s.sampled_tz
 from jsonb_to_recordset(p_samples) as s(id uuid,session_id uuid,continuity_id uuid,
  observed_at timestamptz,sport_mode integer,sampled_tz text)
 on conflict(user_id,id) do nothing;
 get diagnostics n=row_count;
 if exists(select 1 from jsonb_to_recordset(p_samples) as s(id uuid,session_id uuid,
    continuity_id uuid,observed_at timestamptz,sport_mode integer,sampled_tz text)
   left join public.sport_energy_samples stored on stored.user_id=owner and stored.id=s.id
   where stored.id is null or (stored.session_id,stored.continuity_id,stored.observed_at,
    stored.sport_mode,stored.sampled_tz) is distinct from
    (s.session_id,s.continuity_id,s.observed_at,s.sport_mode,s.sampled_tz)) then
  raise exception 'SPORT_ENERGY_OPERATION_CONFLICT' using errcode='23505';
 end if;
 select jsonb_agg(distinct s->>'id') into acknowledged
 from jsonb_array_elements(p_samples) s;
 return jsonb_build_object('inserted',n,'acknowledged_ids',acknowledged);
end;
$$;
revoke all on function public.ingest_sport_energy(jsonb) from public,anon;
grant execute on function public.ingest_sport_energy(jsonb) to authenticated;

-- Preserve the existing export/delete APIs while adding the new evidence domain.
do $$ declare definition text; patched text; begin
 definition:=pg_get_functiondef('public.export_all()'::regprocedure);
 patched:=replace(definition,'''sport_heart_rate_samples'',',
  '''sport_energy_samples'', (select coalesce(jsonb_agg(to_jsonb(s) order by s.observed_at,s.id), ''[]''::jsonb) from public.sport_energy_samples s where s.user_id=(select auth.uid())), ''sport_heart_rate_samples'',');
 if patched=definition then raise exception 'SPORT_ENERGY_EXPORT_ANCHOR_MISSING'; end if;
 execute patched;
 definition:=pg_get_functiondef('public.account_delete(text)'::regprocedure);
 if position('nb.account_delete_legacy_oxygen' in definition)>0 then
  definition:=pg_get_functiondef('nb.account_delete_legacy_oxygen(text)'::regprocedure);
 end if;
 patched:=replace(definition,'delete from public.sport_heart_rate_samples',
  'delete from public.sport_energy_samples where user_id=v_user; delete from public.sport_heart_rate_samples');
 if patched=definition then raise exception 'SPORT_ENERGY_DELETE_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

-- Only adjacent, durable reports in the same continuity establish an energy
-- interval. Intersections are split at every boundary and deterministically owned
-- once, so overlapping/replayed sessions cannot add the same second twice.
create or replace function nb.strength_energy_ticks(p_user uuid,p_user_day date)
returns table(ts timestamptz,observed_seconds numeric,excess_met_seconds numeric)
language sql stable set search_path='' as $$
 with limits as materialized (
  select b.starts_at lo,least(b.ends_at,nb.calculation_instant(p_user,p_user_day)) hi
  from nb.calculation_profile(p_user,p_user_day) p
  cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b
 ), samples as materialized (
  select distinct on(s.session_id,s.continuity_id,s.observed_at)
   s.id,s.session_id,s.continuity_id,s.observed_at,
   nb.strength_met(s.sport_mode) met
  from public.sport_energy_samples s cross join limits l
  where s.user_id=p_user and nb.strength_met(s.sport_mode) is not null
   and s.observed_at>=l.lo-interval '15 seconds' and s.observed_at<=l.hi
  order by s.session_id,s.continuity_id,s.observed_at,s.id desc
 ), pairs as (
  select s.*,lead(s.observed_at) over(
   partition by s.session_id,s.continuity_id order by s.observed_at) finish
  from samples s
 ), intervals as materialized (
  select p.id,p.observed_at original_start,greatest(p.observed_at,l.lo) a,
   least(p.finish,l.hi) b,p.met
  from pairs p cross join limits l
  where p.finish>p.observed_at and p.finish-p.observed_at<=interval '15 seconds'
   and p.finish>l.lo and p.observed_at<l.hi
 ), pieces as materialized (
  select t.ts,i.id,i.original_start,greatest(i.a,t.ts) a,
   least(i.b,t.ts+interval '5 minutes') b,i.met
  from intervals i cross join limits l
  cross join lateral generate_series(date_bin(interval '5 minutes',i.a,l.lo),
   date_bin(interval '5 minutes',i.b-interval '1 microsecond',l.lo),
   interval '5 minutes') t(ts)
 ), boundaries as (
  select ts,a boundary from pieces union select ts,b from pieces
 ), spans as (
  select ts,boundary a,lead(boundary) over(partition by ts order by boundary) b
  from boundaries
 ), owned as (
  select distinct on(s.ts,s.a) s.ts,s.a,s.b,p.met
  from spans s join pieces p on p.ts=s.ts and p.a<=s.a and p.b>=s.b
  where s.b>s.a
  order by s.ts,s.a,p.original_start desc,p.id desc
 )
 select o.ts,sum(extract(epoch from(o.b-o.a))),
  sum(extract(epoch from(o.b-o.a))*greatest(o.met-1,0))
 from owned o group by o.ts;
$$;

-- Keep resting energy unchanged. Within a strength interval, replace the same
-- seconds of coarse origin MET rather than adding a second activity estimate.
create or replace function nb.fuel_components(p_user uuid,p_user_day date)
returns table(bmr_kcal integer,active_kcal integer,bmr_full integer)
language plpgsql stable set search_path='' as $$
declare
 v_tz text; v_lo timestamptz; v_hi timestamptz; v_asof timestamptz;
 v_weight numeric; v_height numeric; v_age numeric; v_sex text;
 v_bmr numeric; v_active numeric; v_elapsed numeric;
begin
 select p.timezone,p.height_cm,p.sex,
  extract(year from age(p_user_day::timestamp,p.birth_date::timestamp))
 into v_tz,v_height,v_sex,v_age from nb.calculation_profile(p_user,p_user_day) p;
 if v_tz is null then return; end if;
 select starts_at,ends_at into v_lo,v_hi from nb.user_day_bounds(p_user_day,v_tz);
 v_asof:=nb.calculation_instant(p_user,p_user_day);
 select w.weight_kg into v_weight from public.weigh_ins w
 where w.user_id=p_user and w.measured_at<=v_asof and w.measured_at<v_hi
 order by (w.measured_at<v_lo) desc,
  case when w.measured_at<v_lo then w.measured_at end desc,w.measured_at asc limit 1;
 if v_weight is not null and v_height is not null and v_age is not null and v_sex is not null then
  v_bmr:=10*v_weight+6.25*v_height-5*v_age+case when v_sex='male' then 5 else -161 end;
 end if;
 with origin as materialized (
  select date_bin(interval '5 minutes',s.ts,v_lo) ts,
   max(greatest(0,nb.activity_met(s.met,s.step)-1)) excess_met
  from public.raw_samples s
  where s.user_id=p_user and s.ts>=v_lo and s.ts<v_hi and s.ts<=v_asof
   and nb.activity_met(s.met,s.step) is not null
  group by date_bin(interval '5 minutes',s.ts,v_lo)
 ), strength as materialized (
  select * from nb.strength_energy_ticks(p_user,p_user_day)
 ), keys as (
  select o.ts from origin o union select s.ts from strength s
 )
 select sum((coalesce(o.excess_met,0)*
    greatest(0,300-least(300,coalesce(s.observed_seconds,0)))+
    coalesce(s.excess_met_seconds,0))*v_weight*7/24000)
 into v_active
 from keys k left join origin o using(ts) left join strength s using(ts);
 v_elapsed:=greatest(0,extract(epoch from(v_asof-v_lo)));
 return query select round(v_bmr*v_elapsed/
   nullif(extract(epoch from(v_hi-v_lo)),0))::integer,
   round(v_active)::integer,round(v_bmr)::integer;
end;
$$;

-- A raw row is not automatically an energy observation. Heart/HRV-only rows used
-- to satisfy measured_burn's 144-row gate even when only one five-minute slot had
-- a usable MET/step value. Count distinct slots that can actually enter the energy
-- ledger, against the real 23/24/25-hour user-day length.
create or replace function nb.measured_burn(p_user uuid, p_user_day date)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz   text;
  v_burn numeric;
  v_days integer;
begin
  select p.timezone into v_tz from nb.calculation_profile(p_user, p_user_day) p;
  if v_tz is null then return null; end if;

  with days as materialized (
    select (p_user_day-g)::date d,b.starts_at,b.ends_at,
      ceil(extract(epoch from(b.ends_at-b.starts_at))/300*0.5)::integer required_slots
    from generate_series(1,14) g
    cross join lateral nb.user_day_bounds((p_user_day-g)::date,v_tz) b
  ), measured as (
    select
      (select c.bmr_full+c.active_kcal from nb.fuel_components(p_user,days.d) c) total,
      (select count(distinct date_bin(interval '5 minutes',s.ts,days.starts_at))
       from public.raw_samples s
       where s.user_id=p_user and s.ts>=days.starts_at and s.ts<days.ends_at
         and s.ts<=nb.calculation_instant(p_user,days.d)
         and nb.activity_met(s.met,s.step) is not null) energy_slots,
      days.required_slots
    from days
  )
  select percentile_cont(0.5) within group(order by total),count(*)
  into v_burn,v_days
  from measured
  where total is not null and energy_slots>=required_slots;

  if coalesce(v_days,0)<3 then return null; end if;
  return v_burn;
end;
$$;

revoke all on function nb.strength_met(integer),nb.strength_energy_ticks(uuid,date),
 nb.fuel_components(uuid,date),nb.measured_burn(uuid,date)
from public,anon,authenticated;

-- Make the changed energy contract visible to publication and replay status.
do $$ declare signature text; definition text; patched text; begin
 foreach signature in array array['nb.settle_day(uuid,date)',
   'nb.recompute_range(uuid,date,date,text)','public.calculation_status(date,date)'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  if position('/energy-1.1' in definition)>0 then continue; end if;
  patched:=replace(definition,'/calc-1','/energy-1.1/calc-1');
  if patched=definition then
   raise exception 'ENERGY_VERSION_ANCHOR_MISSING: %',signature;
  end if;
  execute patched;
 end loop;
end $$;

-- Every stored budget can depend on the old false-positive coverage decision.
-- Publish the same energy weights used by settlement, separately from sensor data.
alter table public.day_fuel add column energy_distribution jsonb;
create function nb.energy_distribution(p_user uuid,p_day date) returns jsonb
language sql stable set search_path='' as $$
 with bounds as (
  select b.starts_at lo,b.ends_at hi,nb.calculation_instant(p_user,p_day) at
  from nb.calculation_profile(p_user,p_day) p
  cross join lateral nb.user_day_bounds(p_day,p.timezone) b
 ), origin as (
  select date_bin(interval '5 minutes',r.ts,b.lo) ts,
   max(greatest(0,nb.activity_met(r.met,r.step)-1)) excess
  from public.raw_samples r cross join bounds b
  where r.user_id=p_user and r.ts>=b.lo and r.ts<b.hi and r.ts<=b.at
   and nb.activity_met(r.met,r.step) is not null group by 1
 ), strength as (select * from nb.strength_energy_ticks(p_user,p_day)),
 points as (
  select coalesce(o.ts,s.ts) ts,
   coalesce(o.excess,0)*greatest(0,300-coalesce(s.observed_seconds,0)) origin_seconds,
   coalesce(s.excess_met_seconds,0) strength_seconds
  from origin o full join strength s using(ts)
 )
 select coalesce(jsonb_agg(jsonb_build_object('epoch',extract(epoch from ts),
  'origin_weight',origin_seconds,'strength_weight',strength_seconds) order by ts),'[]'::jsonb)
 from points;
$$;
revoke all on function nb.energy_distribution(uuid,date) from public,anon,authenticated;
do $$ declare definition text; patched text; begin
 definition:=pg_get_functiondef('nb.on_fuel_settled()'::regprocedure);
 patched:=replace(definition,'select * into v_c from nb.fuel_components',
  'new.energy_distribution := nb.energy_distribution(new.user_id,v_day); select * into v_c from nb.fuel_components');
 if patched=definition then raise exception 'ENERGY_DISTRIBUTION_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

select nb.invalidate_calculation(user_id,min(user_day))
from public.daily_results group by user_id;
