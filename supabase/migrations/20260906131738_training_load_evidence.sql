-- One contribution ledger for the ring, curve, zones, segments and evidence.
-- Fine HR uses bounded sample-and-hold intervals: a report holds only until the
-- next report in the same continuity, at most 15 seconds away. No extrapolation.
create or replace function nb.training_heart_intervals(p_user uuid,p_user_day date)
returns table(ts timestamptz,starts_at timestamptz,ends_at timestamptz,heart smallint)
language sql stable set search_path='' as $$
 with limits as materialized (
  select b.starts_at lo,least(b.ends_at,nb.calculation_instant(p_user,p_user_day)) hi
  from nb.calculation_profile(p_user,p_user_day) p
  cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b
 ), samples as materialized (
  select distinct on(s.session_id,s.continuity_id,s.observed_at) s.*
  from public.sport_heart_rate_samples s cross join limits l
  where s.user_id=p_user and s.observed_at>=l.lo-interval '15 seconds' and s.observed_at<=l.hi
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
$$;

create or replace function nb.training_load_ticks(p_user uuid,p_user_day date)
returns table(ts timestamptz,heart smallint,steps integer,z smallint,raw numeric,
 zone_seconds numeric[],observed_seconds numeric,hr_seconds numeric,movement_seconds numeric,
 hr_weighted_sum numeric,hr_peak smallint)
language sql stable set search_path='' as $$
 with profile as materialized (
  select nb.hr_max(p.birth_date) maximum,nb.hr_rest(p_user,p_user_day,p.timezone) resting,
   b.starts_at lo,b.ends_at day_end,nb.calculation_instant(p_user,p_user_day) hi
  from nb.calculation_profile(p_user,p_user_day) p
  cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b
 ), coarse as materialized (
  select o.*,case when o.heart between 1 and 250 then o.heart end valid_heart,
   nb.activity_met(o.met,o.steps) movement_met,
   o.met between 0.5 and 25 or o.steps>0 movement_observed
  from nb.training_observations(p_user,p_user_day) o
 ), fine as materialized (
  select f.*,extract(epoch from(f.ends_at-f.starts_at)) seconds,
   case when p.maximum>p.resting then
    nb.zone_of(least(1,greatest(0,(f.heart-p.resting)/(p.maximum-p.resting)))) end zone
  from nb.training_heart_intervals(p_user,p_user_day) f cross join profile p
 ), fine_totals as materialized (
  select f.ts,sum(f.seconds) seconds,sum(f.seconds*f.heart) weighted_heart,max(f.heart) peak,
   sum(nb.zone_weight(f.zone)*f.seconds/60) hr_raw,
   array[sum(f.seconds) filter(where zone=0),sum(f.seconds) filter(where zone=1),
    sum(f.seconds) filter(where zone=2),sum(f.seconds) filter(where zone=3),
    sum(f.seconds) filter(where zone=4),sum(f.seconds) filter(where zone=5)] zones
  from fine f group by f.ts
 ), reported_peaks as materialized (
  -- Endpoints and lone reports remain valid peak measurements even though they
  -- establish no duration and therefore cannot increase load or time coverage.
  select date_bin(interval '5 minutes',s.observed_at,p.lo) ts,max(s.heart_rate) peak
  from public.sport_heart_rate_samples s cross join profile p
  where s.user_id=p_user and s.observed_at>=p.lo and s.observed_at<p.day_end and s.observed_at<=p.hi
  group by date_bin(interval '5 minutes',s.observed_at,p.lo)
 ), bucket_keys as (select c.ts from coarse c union select f.ts from fine_totals f union select r.ts from reported_peaks r),
 pieces as (
  select k.ts,c.steps,c.valid_heart,c.movement_met,c.observed,c.movement_observed,
   case when c.valid_heart is not null and p.maximum>p.resting then
    nb.zone_of(least(1,greatest(0,(c.valid_heart-p.resting)/(p.maximum-p.resting)))) end coarse_zone,
   case when c.valid_heart is not null then 300-coalesce(f.seconds,0) else 0 end coarse_hr_seconds,
   coalesce(f.seconds,0) fine_seconds,f.weighted_heart,greatest(f.peak,r.peak) peak,f.hr_raw,f.zones
  from bucket_keys k left join coarse c using(ts) left join fine_totals f using(ts) left join reported_peaks r using(ts) cross join profile p
 ), totals as (
  select b.*,array(select coalesce(b.zones[g+1],0)+
    case when b.coarse_zone=g then b.coarse_hr_seconds else 0 end from generate_series(0,5) g) all_zones,
   b.coarse_hr_seconds+b.fine_seconds all_hr_seconds,
   coalesce(b.valid_heart*b.coarse_hr_seconds,0)+coalesce(b.weighted_heart,0) all_weighted_heart,
   case when b.observed then 300 else b.fine_seconds end all_observed_seconds,
   case when b.movement_observed then 300 else 0 end movement_observed_seconds,
   case when b.coarse_zone is not null or b.hr_raw is not null then
    coalesce(nb.zone_weight(b.coarse_zone)*b.coarse_hr_seconds/60,0)+coalesce(b.hr_raw,0) end total_hr_raw
  from pieces b
 )
 select t.ts,round(t.all_weighted_heart/nullif(t.all_hr_seconds,0))::smallint,t.steps,
  (select max(g)::smallint from generate_series(0,5) g where t.all_zones[g+1]>0),
  greatest(t.total_hr_raw,case when t.movement_met is not null then greatest(0,t.movement_met-1)*0.375 end),
  t.all_zones,t.all_observed_seconds,t.all_hr_seconds,t.movement_observed_seconds,
  t.all_weighted_heart,greatest(t.valid_heart,t.peak)
 from totals t;
$$;

create or replace function nb.activity_ticks(p_user uuid,p_user_day date)
returns table(ts timestamptz,heart smallint,steps integer,z smallint,raw numeric)
language sql stable set search_path='' as $$
 select t.ts,t.heart,t.steps,t.z,t.raw from nb.training_load_ticks(p_user,p_user_day) t where t.raw is not null;
$$;

create or replace function nb.compute_training(p_user uuid,p_user_day date)
returns table(training_load numeric,zone_minutes smallint[],peak_hr smallint,coverage numeric,curve jsonb)
language sql stable set search_path='' as $$
 with ticks as materialized (select * from nb.training_load_ticks(p_user,p_user_day)),
 -- Zero-filled placeholders retain a zero movement estimate but do not draw
 -- an observed curve through missing evidence. Their raw contribution is zero.
 cumulative as (select t.ts,sum(t.raw) over(order by t.ts) running from ticks t
  where t.raw is not null and t.observed_seconds>0),
 bounds as (select greatest(0,extract(epoch from(nb.calculation_instant(p_user,p_user_day)-b.starts_at))) elapsed
  from nb.calculation_profile(p_user,p_user_day) p cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b)
 select case when count(t.raw)=0 then null else least(20.9,round(21*(1-exp(-sum(t.raw)/60)),1)) end,
 case when exists(select 1 from ticks where z is not null) then
  array[floor(sum(zone_seconds[2])/60),floor(sum(zone_seconds[3])/60),floor(sum(zone_seconds[4])/60),
    floor(sum(zone_seconds[5])/60),floor(sum(zone_seconds[6])/60)]::smallint[] end,
 max(t.hr_peak),round(case when (select elapsed from bounds)>0 then least(1,coalesce(sum(t.observed_seconds),0)/(select elapsed from bounds)) else 0 end,2),
 coalesce((select jsonb_agg(jsonb_build_array(extract(epoch from c.ts)::bigint,
  least(20.9,round(21*(1-exp(-c.running/60)),1))) order by c.ts) from cumulative c),'[]'::jsonb)
 from ticks t;
$$;

create or replace function nb.compute_segments(p_user uuid,p_user_day date)
returns jsonb language sql stable set search_path='' as $$
 with ticks as materialized (select t.*,coalesce((select sum(s) from unnest(t.zone_seconds[2:6]) s),0) elevated_seconds
  from nb.training_load_ticks(p_user,p_user_day) t where t.raw is not null),
 boundaries as (
  select t.*,case when coalesce(t.z,0)>=1 and coalesce(lag(t.z) over(order by t.ts),0)>=1
   and t.ts-lag(t.ts) over(order by t.ts)<=interval '5 minutes' then 0 else 1 end boundary from ticks t
 ), runs as (select b.*,sum(boundary) over(order by ts) run from boundaries b),
 blocks as (
  select min(ts) at,round(sum(elevated_seconds)/60)::integer minutes,
   round(sum(hr_weighted_sum)/nullif(sum(hr_seconds),0)) avg_hr,sum(raw) raw,run
  from runs where z>=1 group by run having sum(elevated_seconds)>=900
 ), total as (select sum(raw) raw,least(20.9,round(21*(1-exp(-sum(raw)/60)),1)) load from ticks),
 ordinary as (
  select min(r.ts) at,sum(r.steps)::integer steps,sum(r.raw) raw from runs r
  where not exists(select 1 from blocks b where b.run=r.run)
 ), rows as (
  select b.at,b.minutes,b.avg_hr,b.raw,'ELEVATED HR'::text name,null::integer steps,false all_day from blocks b
  union all select o.at,null,null,o.raw,'STEPS & MOVEMENT',o.steps,true from ordinary o where o.at is not null
 ), cumulative as (select r.*,sum(r.raw) over(order by r.at) running from rows r),
 allocated as (
  select c.at,c.minutes,c.avg_hr,coalesce(round(t.load*c.running/nullif(t.raw,0),1)
   -round(t.load*(c.running-c.raw)/nullif(t.raw,0),1),0) delta,c.name,c.steps,c.all_day
  from cumulative c cross join total t
 )
 select coalesce(jsonb_agg(to_jsonb(a) order by a.at),'[]'::jsonb) from allocated a;
$$;

create or replace function nb.training_evidence(p_user uuid,p_user_day date)
returns jsonb language sql stable set search_path='' as $$
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
  'model_kind','activity_estimate','fine_hr_method','bounded_sample_hold','zone_minutes_rounding','floor_each_zone')
 from profile p cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b cross join details d cross join totals t;
$$;

revoke all on function nb.training_heart_intervals(uuid,date),nb.training_load_ticks(uuid,date),
 nb.activity_ticks(uuid,date),nb.compute_training(uuid,date),nb.compute_segments(uuid,date),
 nb.training_evidence(uuid,date) from public,anon,authenticated;
select nb.invalidate_calculation(user_id,min(user_day)) from public.daily_results group by user_id;
