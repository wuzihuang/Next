-- Sleep-led daily guidance and one time-ordered load ledger. Facts, ownership,
-- ingestion receipts and the 0–21 scale are unchanged. All helpers stay private.
create function nb.training_zone(p_heart numeric,p_max numeric,p_rest numeric)
returns smallint language sql immutable set search_path='' as $$
 select case when p_heart between 1 and 250 and p_max>0 then
  case when p_max>p_rest then nb.zone_of(least(1,greatest(0,(p_heart-p_rest)/(p_max-p_rest))))
  -- No invented resting HR while the personal night baseline is being collected.
  -- Age-based maximum zones are explicitly published as an early estimate.
  else case when p_heart/p_max>=0.9 then 5 when p_heart/p_max>=0.8 then 4
   when p_heart/p_max>=0.7 then 3 when p_heart/p_max>=0.6 then 2
   when p_heart/p_max>=0.5 then 1 else 0 end::smallint end end;
$$;

create function nb.training_load_value(p_raw numeric)
returns numeric language sql immutable set search_path='' as $$
 select least(20.9,21*(1-exp(-greatest(0,p_raw)/60)));
$$;

-- Split coarse slots at every fine observation boundary. Each second has one HR
-- owner and one movement owner, even when sessions overlap or are replayed.
create function nb.training_ledger_uncached(p_user uuid,p_user_day date)
returns table(ts timestamptz,starts_at timestamptz,ends_at timestamptz,
 session_id uuid,sport_mode integer,heart smallint,z smallint,raw numeric,
 observed_seconds numeric,hr_seconds numeric,movement_seconds numeric,sustained boolean)
language sql stable set search_path='' as $$
 with profile as materialized (
  select nb.hr_max(p.birth_date) maximum,nb.hr_rest(p_user,p_user_day,p.timezone) resting,
   b.starts_at lo,least(b.ends_at,nb.calculation_instant(p_user,p_user_day)) hi,b.ends_at day_end
  from nb.calculation_profile(p_user,p_user_day) p
  cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b
 ), coarse as materialized (
  select o.*,case when o.heart between 1 and 250 then o.heart end valid_heart,
   nb.activity_met(o.met,o.steps) movement_met,
   coalesce(o.met between 0.5 and 25 or o.steps>0,false) movement_observed
  from nb.training_observations(p_user,p_user_day) o
 ), reports as materialized (
  select 'hr' kind,s.id,s.session_id,s.continuity_id,s.observed_at,s.sport_mode,s.heart_rate heart,null::numeric met
  from public.sport_heart_rate_samples s cross join profile p
  where s.user_id=p_user and s.observed_at>=p.lo-interval '15 seconds'
   and s.observed_at<=p.hi+case when p.hi=p.day_end then interval '15 seconds' else interval '0 seconds' end
  union all
  select 'met',s.id,s.session_id,s.continuity_id,s.observed_at,s.sport_mode,null::smallint,nb.strength_met(s.sport_mode)
  from public.sport_energy_samples s cross join profile p
  where s.user_id=p_user and s.observed_at>=p.lo-interval '15 seconds'
   and s.observed_at<=p.hi+case when p.hi=p.day_end then interval '15 seconds' else interval '0 seconds' end
 ), unique_reports as (
  select distinct on(kind,session_id,continuity_id,observed_at) * from reports
  order by kind,session_id,continuity_id,observed_at,id desc
 ), pairs as (
  select r.*,lead(r.observed_at) over w finish,lead(r.sport_mode) over w next_mode
  from unique_reports r window w as(partition by kind,session_id,continuity_id order by observed_at)
 ), intervals as materialized (
  select r.*,greatest(r.observed_at,p.lo) a,least(r.finish,p.hi) b
  from pairs r cross join profile p where r.finish>r.observed_at
   and r.finish-r.observed_at<=interval '15 seconds' and r.finish>p.lo and r.observed_at<p.hi
   and r.sport_mode is not distinct from r.next_mode
 ), pieces as materialized (
  select g.ts,i.*,greatest(i.a,g.ts) piece_a,least(i.b,g.ts+interval '5 minutes') piece_b
  from intervals i cross join profile p
  cross join lateral generate_series(date_bin(interval '5 minutes',i.a,p.lo),
   date_bin(interval '5 minutes',i.b-interval '1 microsecond',p.lo),interval '5 minutes') g(ts)
 ), boundaries as (
  select ts,ts boundary from coarse union select ts,ts+interval '5 minutes' from coarse
  union select ts,piece_a from pieces union select ts,piece_b from pieces
 ), spans as (
  select ts,boundary a,lead(boundary) over(partition by ts order by boundary) b from boundaries
 ), owned as (
  select s.*,coalesce(h.heart,c.valid_heart) measured_heart,
   coalesce(e.met,c.movement_met) movement_met,
   coalesce(e.session_id,case when h.sport_mode is not null then h.session_id end) owner,
   coalesce(e.sport_mode,h.sport_mode) mode,
   extract(epoch from(s.b-s.a)) seconds,
   coalesce(c.observed,false) or h.id is not null or e.id is not null observed,
   c.movement_observed or e.id is not null movement_observed
  from spans s left join coarse c using(ts)
  left join lateral(select i.* from pieces i where i.ts=s.ts and i.kind='hr'
   and i.piece_a<=s.a and i.piece_b>=s.b order by i.observed_at desc,i.id desc limit 1) h on true
  left join lateral(select i.* from pieces i where i.ts=s.ts and i.kind='met'
   and i.piece_a<=s.a and i.piece_b>=s.b order by i.observed_at desc,i.id desc limit 1) e on true
  where s.b>s.a
 ), zoned as materialized (
  select o.*,nb.training_zone(o.measured_heart,p.maximum,p.resting) zone from owned o cross join profile p
 ), buckets as (
  select ts,max(zone) zone,coalesce(sum(seconds) filter(where zone>=2),0) exercise_seconds from zoned group by ts
 ), boundaries2 as (
  select b.*,case when b.zone>=1 and lag(b.zone) over(order by ts)>=1
   and ts-lag(ts) over(order by ts)<=interval '5 minutes' then 0 else 1 end boundary from buckets b
 ), runs as (select b.*,sum(boundary) over(order by ts) run from boundaries2 b),
 graded as (
  select r.*,coalesce(zone>=1 and sum(exercise_seconds) over(partition by run)>=900,false) sustained from runs r
 ), rates as (
  select z.*,g.sustained,
   nb.zone_weight(z.zone)*z.seconds/60 * case when z.owner is not null or g.sustained then 1 else 0.25 end hr_raw,
   case when z.movement_met is not null then greatest(0,z.movement_met-1)*z.seconds*0.375/300
    * case when z.owner is not null or g.sustained then 1 else 0.25 end end movement_raw
  from zoned z join graded g using(ts)
 )
 select ts,a,b,owner,mode,measured_heart,zone,
  -- Compare only signals covering the same seconds. Comparing whole-bucket sums
  -- could erase a strength interval when cardio arrives later in that bucket.
  greatest(hr_raw,movement_raw),
  case when observed then seconds else 0 end,
  case when measured_heart is not null then seconds else 0 end,
  case when movement_observed then seconds else 0 end,sustained from rates;
$$;

-- Reused by the ring, curve, per-session receipt and breakdown within one settle.
create function nb.training_ledger(p_user uuid,p_user_day date)
returns table(ts timestamptz,starts_at timestamptz,ends_at timestamptz,
 session_id uuid,sport_mode integer,heart smallint,z smallint,raw numeric,
 observed_seconds numeric,hr_seconds numeric,movement_seconds numeric,sustained boolean)
language plpgsql stable set search_path='' as $$
declare hit jsonb;
begin
 if current_setting('nb.settling_day',true) is distinct from p_user::text||'/'||p_user_day::text then
  return query select * from nb.training_ledger_uncached(p_user,p_user_day); return;
 end if;
 hit:=nullif(current_setting('nb.training_ledger_memo',true),'')::jsonb;
 if hit is null then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into hit from nb.training_ledger_uncached(p_user,p_user_day) t;
  perform set_config('nb.training_ledger_memo',hit::text,true);
 end if;
 return query select * from jsonb_to_recordset(hit) as t(ts timestamptz,starts_at timestamptz,ends_at timestamptz,
  session_id uuid,sport_mode integer,heart smallint,z smallint,raw numeric,
  observed_seconds numeric,hr_seconds numeric,movement_seconds numeric,sustained boolean);
end;
$$;

create or replace function nb.training_load_ticks_uncached(p_user uuid,p_user_day date)
returns table(ts timestamptz,heart smallint,steps integer,z smallint,raw numeric,
 zone_seconds numeric[],observed_seconds numeric,hr_seconds numeric,movement_seconds numeric,
 hr_weighted_sum numeric,hr_peak smallint)
language sql stable set search_path='' as $$
 with ledger as materialized (select * from nb.training_ledger(p_user,p_user_day)),
 bounds as (
  select b.starts_at lo,least(b.ends_at,nb.calculation_instant(p_user,p_user_day)) hi,b.ends_at day_end
  from nb.calculation_profile(p_user,p_user_day) p cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b
 ), peaks as (
  select date_bin(interval '5 minutes',s.observed_at,b.lo) ts,max(s.heart_rate) peak
  from public.sport_heart_rate_samples s cross join bounds b
  where s.user_id=p_user and s.observed_at>=b.lo and s.observed_at<b.day_end and s.observed_at<=b.hi group by 1
 ), totals as (
  select l.ts,max(l.z) z,sum(l.raw) raw,sum(l.observed_seconds) observed,sum(l.hr_seconds) hrs,
   sum(l.movement_seconds) movement,sum(l.heart*l.hr_seconds) weighted,max(l.heart) peak,
   array[coalesce(sum(l.hr_seconds) filter(where l.z=0),0),coalesce(sum(l.hr_seconds) filter(where l.z=1),0),
    coalesce(sum(l.hr_seconds) filter(where l.z=2),0),coalesce(sum(l.hr_seconds) filter(where l.z=3),0),
    coalesce(sum(l.hr_seconds) filter(where l.z=4),0),coalesce(sum(l.hr_seconds) filter(where l.z=5),0)] zones
  from ledger l group by l.ts
 ), keys as(select ts from totals union select ts from peaks)
 select k.ts,round(t.weighted/nullif(t.hrs,0))::smallint,o.steps,t.z,t.raw,
  coalesce(t.zones,array[0,0,0,0,0,0]::numeric[]),coalesce(t.observed,0),coalesce(t.hrs,0),coalesce(t.movement,0),
  coalesce(t.weighted,0),greatest(t.peak,p.peak)
 from keys k left join totals t using(ts) left join peaks p using(ts)
 left join nb.training_observations(p_user,p_user_day) o using(ts);
$$;

-- Differences along the nonlinear curve. These are contributions, not standalone
-- workout scores added to an already compressed daily score.
create function nb.training_contributions(p_user uuid,p_user_day date)
returns table(ts timestamptz,starts_at timestamptz,ends_at timestamptz,session_id uuid,sport_mode integer,
 heart smallint,z smallint,raw numeric,observed_seconds numeric,hr_seconds numeric,sustained boolean,
 load_before numeric,load_after numeric,load_delta numeric,displayed_delta numeric)
language sql stable set search_path='' as $$
 with ordered as (
  select l.*,sum(coalesce(l.raw,0)) over(order by l.starts_at,l.ends_at) running
  from nb.training_ledger(p_user,p_user_day) l where l.raw is not null or l.session_id is not null
 ), scored as (
  select o.*,nb.training_load_value(running-coalesce(raw,0)) before,nb.training_load_value(running) after from ordered o
 )
 select ts,starts_at,ends_at,session_id,sport_mode,heart,z,raw,observed_seconds,hr_seconds,sustained,
  before,after,after-before,round(after,1)-round(before,1) from scored;
$$;

create function nb.training_sessions(p_user uuid,p_user_day date)
returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(s) order by s.started_at,s.session_id),'[]'::jsonb) from (
  select session_id,max(sport_mode) sport_mode,min(starts_at) started_at,max(ends_at) ended_at,
   sum(observed_seconds) observed_seconds,sum(raw) raw_load,sum(load_delta) load_delta,
   sum(displayed_delta) displayed_delta,min(load_before) load_before,max(load_after) load_after
  from nb.training_contributions(p_user,p_user_day) where session_id is not null group by session_id
 ) s;
$$;

create or replace function nb.compute_segments(p_user uuid,p_user_day date)
returns jsonb language sql stable set search_path='' as $$
 with ticks as materialized(select * from nb.training_contributions(p_user,p_user_day) where raw is not null),
 boundaries as (
  select t.*,case when t.sustained and lag(t.sustained) over(order by starts_at)
   and starts_at-lag(ends_at) over(order by starts_at)<=interval '5 minutes'
   and session_id is not distinct from lag(session_id) over(order by starts_at) then 0 else 1 end boundary from ticks t
 ), runs as(select b.*,sum(boundary) over(order by starts_at) run from boundaries b),
 labelled as (
  select r.*,case when session_id is not null then session_id::text
   when sustained then 'hr/'||run::text else 'ordinary' end key from runs r
 ), rows as (
  select min(starts_at) at,case when key='ordinary' then null else round(sum(observed_seconds)/60)::integer end minutes,
   round(sum(heart*hr_seconds)/nullif(sum(hr_seconds),0)) avg_hr,
   sum(displayed_delta) delta,
   case when key='ordinary' then 'STEPS & MOVEMENT' when key like 'hr/%' then 'ELEVATED HR' else 'RECORDED SESSION' end name,
   case when key='ordinary' then (select sum(o.steps)::integer from nb.training_observations(p_user,p_user_day) o
     where exists(select 1 from labelled l where l.ts=o.ts and l.key='ordinary')) end steps,
   key='ordinary' all_day,case when key not like 'hr/%' and key<>'ordinary' then key::uuid end session_id
  from labelled group by key
 )
 select coalesce(jsonb_agg(to_jsonb(r) order by at),'[]'::jsonb) from rows r;
$$;

-- Settlement already computed reserve. Reuse that exact result for target
-- composition instead of repeating the whole reserve model for each reader.
create function nb.training_reserve(p_user uuid,p_user_day date)
returns table(wake_value smallint,current_value smallint,min_value smallint,drivers jsonb)
language plpgsql stable set search_path='' as $$
declare hit jsonb;
begin
 if current_setting('nb.settling_day',true)=p_user::text||'/'||p_user_day::text then
  hit:=nullif(current_setting('nb.training_reserve_memo',true),'')::jsonb;
 end if;
 if hit is null then return query select * from nb.compute_reserve(p_user,p_user_day);
 else return query select * from jsonb_to_record(hit) as r(wake_value smallint,current_value smallint,min_value smallint,drivers jsonb);
 end if;
end;
$$;

-- Sleep is required, with recovery physiology and duration carrying most weight.
-- Coefficients are bounded product guidance, not an individually validated dose.
create function nb.training_target(p_user uuid,p_user_day date,p_wake smallint)
returns jsonb language plpgsql stable set search_path='' as $$
declare n record; score public.night_score%rowtype; sleep_minutes numeric; sleep_readiness numeric;
 readiness numeric; target numeric; recent numeric; typical numeric; nrecent integer; nhistory integer;
 penalty numeric:=0; limited boolean:=true;
begin
 select * into n from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day);
 if n.wake_at is not null and n.wake_at<=nb.calculation_instant(p_user,p_user_day)
  and n.wake_at>n.sleep_start then
  select * into score from public.night_score where user_id=p_user and user_day=p_user_day;
  if found then
   sleep_minutes:=(score.inputs->>'duration_min')::numeric;
   sleep_readiness:=nb.weighted_present(array[score.duration_score,score.recovery_score,
    score.architecture_score,score.regularity_score]::numeric[],array[40,40,10,10]::numeric[]);
   readiness:=nb.weighted_present(array[sleep_readiness,p_wake]::numeric[],array[80,20]::numeric[]);
   limited:=score.recovery_score is null or score.personal_weight<1 or p_wake is null;
  end if;
 end if;
 -- Only completed, sufficiently recorded days can describe recent training.
 -- All dates precede today, so today's exercise never moves its own goalposts.
 with history as (
  select d.user_day,d.training_load from public.daily_results d join public.daily_training t on t.result_id=d.id
  where d.user_id=p_user and d.user_day between p_user_day-28 and p_user_day-1
   and d.training_load is not null and d.algo_version=nb.calculation_version()
   and (t.evidence->>'recorded_minutes')::numeric>=360
   and (t.evidence->>'recorded_minutes')::numeric>=0.5*(t.evidence->>'elapsed_minutes')::numeric
 ) select avg(training_load) filter(where user_day>=p_user_day-3),
   percentile_cont(0.5) within group(order by training_load) filter(where user_day<p_user_day-3),
   count(*) filter(where user_day>=p_user_day-3),count(*) filter(where user_day<p_user_day-3)
 into recent,typical,nrecent,nhistory from history;
 if nrecent>=2 and nhistory>=7 then penalty:=least(2,greatest(0,recent-typical)*0.35); end if;
 if readiness is not null and sleep_minutes>0 then
  target:=round(greatest(4,least(16,4+12*readiness/100-penalty)),1);
  -- Good autonomic readings cannot erase a severely shortened night.
  if sleep_minutes<360 then target:=least(target,8+3*greatest(0,sleep_minutes-240)/120); end if;
  target:=round(target,1);
 end if;
 return jsonb_build_object('version','target-1.0','target',target,
  'lower',case when target is not null then greatest(0,target-2) end,
  'upper',case when target is not null then least(20,target+2) end,
  'sleep_score',case when sleep_minutes is not null then score.score end,'sleep_minutes',sleep_minutes,
  'recovery_score',case when sleep_minutes is not null then score.recovery_score end,
  'wake_reserve',p_wake,'readiness',round(readiness,1),'recent_load',round(recent,1),
  'history_days',coalesce(nhistory,0)+coalesce(nrecent,0),'recent_adjustment',-penalty,'limited',limited);
end;
$$;

-- A received endpoint just after a closed day's midnight proves duration before
-- that boundary. Only that endpoint is read; integration still clips at midnight.
CREATE OR REPLACE FUNCTION nb.training_heart_intervals(p_user uuid, p_user_day date)
 RETURNS TABLE(ts timestamp with time zone, starts_at timestamp with time zone, ends_at timestamp with time zone, heart smallint)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with limits as materialized (
  select b.starts_at lo,least(b.ends_at,nb.calculation_instant(p_user,p_user_day)) hi,b.ends_at day_end
  from nb.calculation_profile(p_user,p_user_day) p
  cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b
 ), samples as materialized (
  select distinct on(s.session_id,s.continuity_id,s.observed_at) s.*
  from public.sport_heart_rate_samples s cross join limits l
  where s.user_id=p_user and s.observed_at>=l.lo-interval '15 seconds' and s.observed_at<=l.hi+case when l.hi=l.day_end then interval '15 seconds' else interval '0 seconds' end
  order by s.session_id,s.continuity_id,s.observed_at,s.id desc
 ), pairs as (
  select s.*,lead(s.observed_at) over(partition by s.session_id,s.continuity_id order by s.observed_at) finish
  from samples s
 ), intervals as materialized (
  select p.id,p.observed_at original_start,greatest(p.observed_at,l.lo) a,least(p.finish,l.hi) b,p.heart_rate
  from pairs p cross join limits l where p.finish>p.observed_at
    and p.finish-p.observed_at<=interval '15 seconds' and p.finish>l.lo and p.observed_at<l.hi
 ), pieces as materialized (
  select t.ts,i.id,i.original_start,greatest(i.a,t.ts) a,least(i.b,t.ts+interval '5 minutes') b,i.heart_rate
  from intervals i cross join limits l
  cross join lateral generate_series(date_bin(interval '5 minutes',i.a,l.lo),
    date_bin(interval '5 minutes',i.b-interval '1 microsecond',l.lo),interval '5 minutes') t(ts)
 ), boundaries as (
  select ts,a boundary from pieces union select ts,b from pieces
 ), spans as (
  select ts,boundary a,lead(boundary) over(partition by ts order by boundary) b from boundaries
 )
 -- Partition the union before choosing an owner. Overlapping sessions therefore
 -- occupy one interval only; the most recently started interval wins, UUID breaks ties.
 select distinct on(s.ts,s.a) s.ts,s.a,s.b,p.heart_rate
 from spans s join pieces p on p.ts=s.ts and p.a<=s.a and p.b>=s.b
 where s.b>s.a order by s.ts,s.a,p.original_start desc,p.id desc;
$function$
;

-- Full publication definitions from the complete local migration rebuild.
CREATE OR REPLACE FUNCTION nb.training_evidence(p_user uuid, p_user_day date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with profile as materialized (select * from nb.calculation_profile(p_user,p_user_day)),
 details as materialized (select d.* from profile p cross join lateral nb.hr_rest_details(p_user,p_user_day,p.timezone) d),
 ticks as materialized (select * from nb.training_load_ticks(p_user,p_user_day)),
 totals as (select coalesce(sum(observed_seconds),0) recorded,coalesce(sum(hr_seconds),0) hr,
  coalesce(sum(movement_seconds),0) movement from ticks)
 select jsonb_build_object(
  'elapsed_minutes',floor(greatest(0,extract(epoch from(nb.calculation_instant(p_user,p_user_day)-b.starts_at)))/60),
  'recorded_minutes',floor(t.recorded/60),'hr_minutes',floor(t.hr/60),'movement_minutes',floor(t.movement/60),
  'recorded_seconds',t.recorded,'hr_seconds',t.hr,'movement_seconds',t.movement,
  'sport_hr_seconds',(select coalesce(sum(extract(epoch from(f.ends_at-f.starts_at))),0) from nb.training_heart_intervals(p_user,p_user_day) f),
  'hr_rest',d.resting,'hr_rest_nights',d.nights,'baseline_estimated',d.estimated or d.resting is null,
  'target',nb.training_target(p_user,p_user_day,(select wake_value from nb.training_reserve(p_user,p_user_day))),
  'sessions',nb.training_sessions(p_user,p_user_day),
  'hr_zone_method',case when d.resting is not null then 'heart_rate_reserve' else 'age_max_estimate' end,
  'model_kind','activity_estimate','fine_hr_method','bounded_sample_hold','zone_minutes_rounding','floor_each_zone')
 from profile p cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b cross join details d cross join totals t;
$function$
;
CREATE OR REPLACE FUNCTION nb.settle_day(p_user uuid, p_user_day date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_train   record;
  v_reserve record;
  v_fuel    record;
  v_call    record;
  v_id      uuid;
  v_prev    text;
  v_algo    text := nb.calculation_version();
  v_hash    text;
begin
  perform set_config('nb.settling_day', p_user::text||'/'||p_user_day::text, true);
  perform set_config('nb.training_ticks_memo', '', true);
  perform set_config('nb.training_ledger_memo', '', true);
  perform set_config('nb.training_reserve_memo', '', true);
  perform nb.refresh_night_score(p_user,p_user_day);
  select * into v_train   from nb.compute_training(p_user, p_user_day);
  select * into v_reserve from nb.compute_reserve(p_user, p_user_day);
  perform set_config('nb.training_reserve_memo', to_jsonb(v_reserve)::text, true);
  select * into v_fuel    from nb.compute_fuel(p_user, p_user_day);
  select * into v_call    from nb.compute_the_call(p_user, p_user_day);

  v_hash := md5(coalesce(v_train.training_load::text, '') ||
                coalesce(v_reserve.wake_value::text, '') ||
                coalesce(v_fuel.kcal_in::text, '') ||
                coalesce(v_fuel.kcal_out::text, '') ||
                coalesce(v_call.fat_delta::text, ''));

  select dr.the_call into v_prev
  from public.daily_results dr
  where dr.user_id = p_user and dr.user_day = p_user_day;

  insert into public.daily_results as d
    (user_id, user_day, training_load, reserve_score, fuel_balance_kcal,
     daily_direction, the_call, the_call_confidence, algo_version, inputs_hash, computed_at, input_revision, result_revision, calculation_as_of, profile_revision)
  values
    (p_user, p_user_day, v_train.training_load, v_reserve.current_value, v_fuel.balance,
     v_fuel.direction, v_call.out_call, coalesce(v_call.out_confidence, 'PENDING'),
     v_algo, v_hash, now(), coalesce(nullif(current_setting('nb.input_revision',true),''),'0')::bigint, extensions.gen_random_uuid(), nb.calculation_clock(), nullif(current_setting('nb.profile_revision',true),'')::bigint)
  on conflict (user_id, user_day) do update set
    training_load = excluded.training_load,
    reserve_score = excluded.reserve_score,
    fuel_balance_kcal = excluded.fuel_balance_kcal,
    daily_direction = excluded.daily_direction,
    the_call = excluded.the_call,
    the_call_confidence = excluded.the_call_confidence,
    algo_version = excluded.algo_version,
    inputs_hash = excluded.inputs_hash,
    computed_at = now(), input_revision = excluded.input_revision, result_revision = excluded.result_revision, calculation_as_of = excluded.calculation_as_of, profile_revision = excluded.profile_revision
  returning d.id into v_id;

  insert into public.daily_training (result_id, user_id, zone_minutes, peak_hr, session_count, curve)
  values (v_id, p_user, coalesce(v_train.zone_minutes, '{0,0,0,0,0}'), v_train.peak_hr, 0,
          coalesce(v_train.curve, '[]'::jsonb))
  on conflict (result_id) do update set
    zone_minutes = excluded.zone_minutes,
    peak_hr = excluded.peak_hr,
    curve = excluded.curve;

  if v_reserve.current_value is not null then
    insert into public.reserve_daily (result_id, user_id, wake_value, min_value, current_value, drain_drivers)
    values (v_id, p_user, v_reserve.wake_value, v_reserve.min_value,
            v_reserve.current_value, v_reserve.drivers)
    on conflict (result_id) do update set
      wake_value = excluded.wake_value,
      min_value = excluded.min_value,
      current_value = excluded.current_value,
      drain_drivers = excluded.drain_drivers;
  end if;

  if v_fuel.intake_state is not null then
    insert into public.day_fuel (result_id, user_id, intake_state, kcal_in, kcal_out, slot_states)
    values (v_id, p_user, v_fuel.intake_state, v_fuel.kcal_in, v_fuel.kcal_out, v_fuel.slot_states)
    on conflict (result_id) do update set
      intake_state = excluded.intake_state,
      kcal_in = excluded.kcal_in,
      kcal_out = excluded.kcal_out,
      slot_states = excluded.slot_states;
  end if;

  -- 10 · the call is never allowed to change silently.
  if v_call.out_call is not null and v_call.out_call is distinct from v_prev then
    insert into public.call_changes (user_id, user_day, call, prev_call, reason, changed_by, algo_version)
    values (p_user, p_user_day, v_call.out_call, v_prev,
            format('fat %s kg / lean %s kg over 7d', v_call.fat_delta, v_call.lean_delta),
            'settle', v_algo);
  end if;

  perform set_config('nb.settling_day', '', true); perform set_config('nb.training_ticks_memo', '', true);
  perform set_config('nb.training_ledger_memo', '', true);
  perform set_config('nb.training_reserve_memo', '', true);
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION nb.recompute_range(p_user uuid, p_from date, p_to date, p_reason text DEFAULT 'manual'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d date; n integer:=0; w nb.calculation_work; tz text; today date; lo date;
 hi timestamptz; tick timestamptz; profile_rev bigint; previous_asof text; previous_day text; recovery_to date; last_day date; deadline timestamptz; next_day date;
begin
 -- Fact writers lock the same row when advancing a revision; concurrent callers
 -- recheck this state after waiting rather than publishing stale output.
 insert into nb.calculation_work(user_id) values(p_user) on conflict do nothing;
 select * into w from nb.calculation_work where user_id=p_user for update;
 perform set_config('nb.night_evidence_memo','',true); perform set_config('nb.reserve_replay_memo','',true);
 select timezone into tz from public.profiles where user_id=p_user and deletion_requested_at is null;
 if tz is null then return 0; end if;
 today:=nb.user_day_of(now(),tz);
 lo:=least(p_from,w.dirty_from);
 -- Fourteen baseline nights plus a full local day must remain available.
 -- An old dirty dependency cannot be skipped: its carry-forward would corrupt
 -- later days. Keep the entire chain pending until archive recovery can replay it.
 select through_day into recovery_to from nb.calculation_recovery_scope where transaction_id=txid_current() and user_id=p_user;
 if w.dirty_from<today-385 and recovery_to is null then return 0; end if;
 if recovery_to is null then lo:=greatest(lo,today-385); end if;
 previous_asof:=current_setting('nb.calculation_as_of',true);
 previous_day:=current_setting('nb.calculation_day',true);
 deadline:=nullif(current_setting('nb.calculation_deadline',true),'')::timestamptz;
 for d in select generate_series(lo,least(greatest(p_to,case when w.dirty_from is not null then today else p_to end),today,coalesce(recovery_to,today)),interval '1 day')::date loop
   select h.revision into profile_rev from nb.profile_history h
     where h.user_id=p_user and h.effective_day<=d order by h.effective_day desc limit 1;
   select ends_at into hi from nb.user_day_bounds(d,(select p.timezone from nb.calculation_profile(p_user,d) p));
   tick:=least(hi,date_bin(interval '1 minute',now(),'2000-01-01'::timestamptz));
   if exists(select 1 from public.daily_results r where r.user_id=p_user and r.user_day=d
       and nb.calculation_result_is_current(r,w.dirty_from,profile_rev,hi,tick)) then continue; end if;
   if deadline is not null and last_day is not null and clock_timestamp()>deadline then next_day:=d; exit; end if;
   perform set_config('nb.calculation_day',d::text,true);
   perform set_config('nb.calculation_as_of',tick::text,true);
   perform nb.refresh_night_hrv(p_user,d);
   perform set_config('nb.input_revision',w.input_revision::text,true);
   perform set_config('nb.profile_revision',profile_rev::text,true);
   perform nb.settle_day(p_user,d);
   last_day:=d; n:=n+1;
 end loop;
 update nb.calculation_work set dirty_from=case when next_day is not null then next_day when recovery_to is not null and last_day<today then last_day+1 else null end where user_id=p_user;
 perform set_config('nb.calculation_as_of',coalesce(previous_asof,''),true);
 perform set_config('nb.calculation_day',coalesce(previous_day,''),true);
 insert into public.recompute_log(algo_version,reason,rows_touched) values('calculation-revisions-1',p_reason||case when next_day is not null then ' (deadline, resumes '||next_day||')' else '' end,n);
 return n;
end;
$function$
;
-- Change only the training revision; independent reserve/fuel revisions survive.
do $$ declare definition text; patched text; begin
 definition:=pg_get_functiondef('nb.calculation_version()'::regprocedure);
 patched:=replace(definition,'tl-2.2/','tl-3.0/');
 if patched=definition then raise exception 'TRAINING_VERSION_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

revoke all on function nb.training_zone(numeric,numeric,numeric),nb.training_load_value(numeric),
 nb.training_ledger_uncached(uuid,date),nb.training_ledger(uuid,date),nb.training_contributions(uuid,date),
 nb.training_sessions(uuid,date),nb.training_target(uuid,date,smallint),nb.training_reserve(uuid,date),nb.training_load_ticks_uncached(uuid,date),
 nb.compute_segments(uuid,date),nb.training_evidence(uuid,date) from public,anon,authenticated;
select nb.invalidate_calculation(user_id,min(user_day)) from public.daily_results group by user_id;
