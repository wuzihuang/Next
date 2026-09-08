-- Two calibration issues, one migration, because both change the same settle chain.
--
-- #23 training load rose almost as fast on an ordinary day as on a training day.
-- Ordinary life spends hours just above the zone-1 floor, and at 0.15/min those hours
-- outweighed the workout that the number is supposed to be about. The zone weights are
-- unchanged — they are shared with the zone display — and so is every workout. What
-- changes is that a tick only earns its full weight inside a *session*: a contiguous run
-- of elevated ticks (zone >= 1, no more than five minutes apart, so a session that dips
-- does not split) holding at least fifteen minutes of zone >= 2 time. Zone 1 is the
-- band's own word for 日常走动: an hour of housework is a run, and it is not a session.
-- Everything outside a session enters the ledger at a quarter weight.
--
-- #24 body battery drained too slowly to describe a day. A hard day of work landed near
-- 60 whatever the night before had been. Three changes: the awake basal is larger and is
-- multiplied by the night's sleep debt (1.0 at seven hours, 1.6 at four or fewer), the
-- movement drain rises steeply once heart rate is genuinely in a training zone so an hour
-- of real work costs about twenty points instead of five, and every drain term is scaled
-- by the remaining charge so the aggressive top of the range does not empty the battery
-- by dinner. The floor of that scale is 0.35, so a truly sleepless day still reaches 0.
--
-- Calibration targets (18 waking hours, ordinary labour):
--   rested night, no workout       100 -> ~49
--   four-hour night, no workout    100 -> ~37
--   four-hour night, one workout   100 -> ~15
--   second day with no sleep at all      -> 0

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
 ), shaped as (
  select t.*,
   (select max(g)::smallint from generate_series(0,5) g where t.all_zones[g+1]>0) zone,
   greatest(t.total_hr_raw,case when t.movement_met is not null then greatest(0,t.movement_met-1)*0.375 end) raw_full,
   coalesce((select sum(s) from unnest(t.all_zones[3:6]) s),0) session_seconds
  from totals t
 -- #23 · the same run rule the segment ledger uses, computed once here so the ring,
 -- the curve, the segments and the evidence all read one number. A run is a maximal
 -- chain of zone >= 1 ticks no more than five minutes apart; it qualifies on the zone 2
 -- and above time inside it, which is what separates a session from a busy afternoon.
 ), boundaries as (
  select s.*,case when coalesce(s.zone,0)>=1 and coalesce(lag(s.zone) over(order by s.ts),0)>=1
    and s.ts-lag(s.ts) over(order by s.ts)<=interval '5 minutes' then 0 else 1 end boundary
  from shaped s
 ), runs as (select b.*,sum(b.boundary) over(order by b.ts) run from boundaries b),
 graded as (
  select r.*,coalesce(r.zone,0)>=1
    and sum(r.session_seconds) over(partition by r.run)>=900 as sustained
  from runs r
 )
 select g.ts,round(g.all_weighted_heart/nullif(g.all_hr_seconds,0))::smallint,g.steps,g.zone,
  case when g.raw_full is null then null
       when g.sustained then g.raw_full
       else 0.25*g.raw_full end,
  g.all_zones,g.all_observed_seconds,g.all_hr_seconds,g.movement_observed_seconds,
  g.all_weighted_heart,greatest(g.valid_heart,g.peak)
 from graded g;
$$;

create or replace function nb.reserve_replay_uncached(p_user uuid, p_user_day date)
returns table (
  ts        timestamptz,
  value     numeric,
  asleep    boolean,
  d_charge  numeric,
  d_basal   numeric,
  d_active  numeric,
  d_stress  numeric
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz       text;
  v_birth    date;
  v_lo       timestamptz;
  v_hi       timestamptz;
  v_anchor   numeric;
  v_rhr      numeric;
  v_hr_max   numeric;
  v_hrv_base numeric;
  v_slept    numeric;
  v_night    numeric;
  v_worn     numeric;
  v_debt     numeric;
begin
  select p.timezone, p.birth_date into v_tz, v_birth
  from nb.calculation_profile(p_user,p_user_day) p where p.user_id = p_user;
  if v_tz is null then return; end if;
  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);

  v_anchor := nb.reserve_anchor(p_user, p_user_day);

  v_rhr    := coalesce((select n.rhr from nb.night_evidence_parts_at(p_user,p_user_day,nb.calculation_instant(p_user,p_user_day)) n),
                       nb.hr_rest(p_user, p_user_day, v_tz), 55);
  v_hr_max := coalesce(nb.hr_max(v_birth), 190);

  with history as materialized (
    select n.hrv from generate_series(p_user_day-14,p_user_day-1,interval '1 day') d
    cross join lateral nb.night_evidence_parts_at(p_user,d::date,nb.calculation_instant(p_user,p_user_day)) n where n.hrv_eligible
  ) select avg(h.hrv) into v_hrv_base from history h;

  -- #24 · sleep debt. Short nights cost more through the day: 1.0 at seven hours,
  -- 1.6 at four or fewer. A night with no sleep at all only counts as sleepless when
  -- the wrist was there to see it — no minutes and no wear is a missing night, which is
  -- the #25 distinction, and it stays neutral rather than charging for absent evidence.
  select count(*)::numeric into v_slept
  from nb.sleep_evidence_minutes(p_user,p_user_day) m where m.stage <> 4;
  if v_slept > 0 then
    v_debt := 1 + 0.6 * least(1, greatest(0, (420 - v_slept) / 180));
  else
    select count(*)::numeric into v_night from generate_series(
      v_lo, least(v_lo + interval '8 hours', nb.calculation_instant(p_user,p_user_day))
              - interval '5 minutes', interval '5 minutes') g;
    select count(distinct s.ts)::numeric into v_worn from public.raw_samples s
    where s.user_id = p_user and s.ts >= v_lo and s.ts < v_lo + interval '8 hours'
      and s.ts <= nb.calculation_instant(p_user,p_user_day)
      and (s.heart is not null or s.hrv is not null or s.stress is not null
           or coalesce(s.step,0) > 0 or coalesce(s.met,1) > 1.05);
    v_debt := case when v_night > 0 and v_worn / v_night >= 0.5 then 1.6 else 1 end;
  end if;

  return query
  with recursive
  night as materialized (
    select s.user_day,nb.charge_multiplier_at(p_user,s.user_day,v_tz,nb.calculation_instant(p_user,p_user_day)) multiplier
    from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day+1) s where s.user_id=p_user
      and s.user_day between p_user_day and p_user_day+1
  ),
  sleep_minutes as materialized (
    select m.ts,max(m.stage) stage,max(m.q*n.multiplier) recovery
    from night n cross join lateral nb.sleep_evidence_minutes(p_user,n.user_day) m
    where m.ts>=v_lo and m.ts<v_hi group by m.ts
  ),
  sleep_evidence as materialized (
    select date_bin(interval '5 minutes',m.ts,v_lo) t,
      least(1,count(*)::numeric/5) recorded_fraction,
      least(1,count(*) filter(where m.stage<>4)::numeric/5) sleep_fraction,
      sum(case when m.stage=4 then 0 else m.recovery end)/5 recovery_effect
    from sleep_minutes m
    group by 1
  ),
  tick_grid as (
    select generate_series(
      v_lo,
      -- 末端由数据决定：上一个完整格子，或最后一个真有采样的格子，取较晚者。
      least(v_hi - interval '5 minutes', greatest(
        date_bin(interval '5 minutes', nb.calculation_instant(p_user,p_user_day), v_lo) - interval '5 minutes',
        coalesce((select max(date_bin(interval '5 minutes', s.ts, v_lo)) from public.raw_samples s
                  where s.user_id = p_user and s.ts >= v_lo
                    and s.ts <= nb.calculation_instant(p_user,p_user_day)), v_lo))),
      interval '5 minutes'
    ) as t
  ),
  observed as (
    select g.t,
           r.heart,
           r.hrv,
           r.stress,
           r.step,
           r.met,
           coalesce(st.recorded_fraction, 0) as recorded_fraction,
           coalesce(st.sleep_fraction, 0) as sleep_fraction,
           coalesce(st.recovery_effect, 0) as recovery_effect
    from tick_grid g
    left join lateral (
      select sample.heart, sample.hrv, sample.stress, sample.step, sample.met
      from public.raw_samples sample
      where sample.user_id = p_user and sample.ts = g.t
      order by (sample.src = 'band') desc
      limit 1
    ) r on true
    left join sleep_evidence st on st.t = g.t
  ),
  fused as (
    select o.*,
           o.heart is not null or o.hrv is not null or o.stress is not null
             or coalesce(o.step, 0) > 0 or coalesce(o.met, 1) > 1.05 as sensor_worn,
           -- #24 · effort costs what it costs. The steps and MET terms stay modest:
           -- they stand in for heart rate when it is missing, not beside it.
           greatest(
             case
               when o.heart is null or v_hr_max <= v_rhr then 0
               when (o.heart - v_rhr) / (v_hr_max - v_rhr) >= 0.85 then 6.40
               when (o.heart - v_rhr) / (v_hr_max - v_rhr) >= 0.70 then 3.60
               when (o.heart - v_rhr) / (v_hr_max - v_rhr) >= 0.55 then 1.20
               when (o.heart - v_rhr) / (v_hr_max - v_rhr) >= 0.40 then 0.30
               when (o.heart - v_rhr) / (v_hr_max - v_rhr) >= 0.30 then 0.06
               else 0
             end,
             least(6.40, 0.12 * greatest(0, coalesce(o.met, 1) - 1)),
             least(6.40, coalesce(o.step, 0)::numeric / 800 * 0.60)
           ) as move
    from observed o
  ),
  feature as (
    select f.*,
           f.recorded_fraction > 0 or f.sensor_worn as worn,
           greatest(0, case
             when f.sensor_worn then 1 - f.sleep_fraction
             else f.recorded_fraction - f.sleep_fraction
           end) as awake_fraction,
           (
             0.15 * greatest(0, coalesce(f.stress, 40) - 40) / 60
             + case when f.hrv is not null and v_hrv_base is not null and v_hrv_base > 0
                    then 0.12 * least(1, greatest(0, (v_hrv_base - f.hrv) / v_hrv_base))
                    else 0 end
           ) * greatest(0.25, 1 - f.move / 6.40) as strain,
           f.sleep_fraction = 0
             and f.sensor_worn
             and f.heart is not null and f.heart <= v_rhr + 8
             and f.stress is not null and f.stress <= 35
             and f.hrv is not null and v_hrv_base is not null and f.hrv >= v_hrv_base * 0.90
             and f.move < 0.03 and f.step is not null and f.step = 0 as quiet
    from fused f
  ),
  numbered as (
    select row_number() over (order by f.t)::integer as n, f.*
    from feature f
  ),
  replay as (
    select 0::integer as n, v_lo as t, v_anchor::numeric as value,
           false as in_sleep, false as observed,
           0::numeric as d_charge, 0::numeric as d_basal,
           0::numeric as d_active, 0::numeric as d_stress,
           0::numeric as quiet_minutes, 0::numeric as rest_used
    union all
    select x.n, x.t, step.next_value, x.sleep_fraction >= 0.5, x.worn,
           r.d_charge + step.effective_charge,
           r.d_basal - step.effective_awake + step.effective_rest,
           r.d_active - step.effective_move,
           r.d_stress - step.effective_strain,
           step.next_quiet_minutes,
           r.rest_used + step.effective_rest
    from replay r
    join numbered x on x.n = r.n + 1
    cross join lateral (
      select case when x.quiet then r.quiet_minutes + 5 else 0 end as next_quiet_minutes
    ) quiet
    cross join lateral (
      select case
        when x.recovery_effect > 0 then
          greatest(0, 95 - r.value)
            * (1 - exp(-0.011 * x.recovery_effect))
        else 0 end as raw_charge,
        case when x.worn then 0.15 * v_debt * x.awake_fraction else 0 end as raw_awake,
        case when x.worn then x.move * x.awake_fraction else 0 end as raw_move,
        case when x.worn then x.strain * x.awake_fraction else 0 end as raw_strain,
        case when x.quiet and quiet.next_quiet_minutes > 20
                       and r.rest_used < 5 and r.value < 80
             then least(5 - r.rest_used, 0.05 * greatest(0, (80 - r.value) / 80))
             else 0 end as raw_rest
    ) raw
    -- #24 · a battery under load. The same request costs less as the reserve empties,
    -- so a steep top of the range never means an empty battery by dinner; the 0.35
    -- floor keeps the drain finite, which is what lets a sleepless day still reach 0.
    cross join lateral (
      select 0.35 + 0.65 * r.value / 100 as k
    ) soft
    cross join lateral (
      select raw.raw_awake * soft.k as awake, raw.raw_move * soft.k as movement,
             raw.raw_strain * soft.k as strain, raw.raw_rest as rest
    ) eff
    cross join lateral (
      select case
        when eff.awake + eff.movement + eff.strain - eff.rest > r.value
          then r.value / nullif(eff.awake + eff.movement + eff.strain - eff.rest, 0)
        else 1 end as drain_scale
    ) scale
    cross join lateral (
      select least(100, greatest(0,
               r.value + raw.raw_charge
               - eff.awake * scale.drain_scale
               - eff.movement * scale.drain_scale
               - eff.strain * scale.drain_scale
               + eff.rest * scale.drain_scale)) as next_value,
             raw.raw_charge as effective_charge,
             eff.awake * scale.drain_scale as effective_awake,
             eff.movement * scale.drain_scale as effective_move,
             eff.strain * scale.drain_scale as effective_strain,
             eff.rest * scale.drain_scale as effective_rest,
             quiet.next_quiet_minutes
    ) step
  )
  select r.t, r.value, r.in_sleep, r.d_charge, r.d_basal, r.d_active, r.d_stress
  from replay r
  where r.n > 0 and r.observed
  order by r.t;
end;
$$;

-- The block the segment card draws must be the same block the ledger paid full weight
-- for, or the page shows an ELEVATED HR row worth almost nothing. Same qualification,
-- same fifteen minutes of zone >= 2; the minutes printed on the row stay the run's
-- elevated time, which is what that row has always meant.
create or replace function nb.compute_segments(p_user uuid,p_user_day date)
returns jsonb language sql stable set search_path='' as $$
 with ticks as materialized (select t.*,
   coalesce((select sum(s) from unnest(t.zone_seconds[2:6]) s),0) elevated_seconds,
   coalesce((select sum(s) from unnest(t.zone_seconds[3:6]) s),0) session_seconds
  from nb.training_load_ticks(p_user,p_user_day) t where t.raw is not null),
 boundaries as (
  select t.*,case when coalesce(t.z,0)>=1 and coalesce(lag(t.z) over(order by t.ts),0)>=1
   and t.ts-lag(t.ts) over(order by t.ts)<=interval '5 minutes' then 0 else 1 end boundary from ticks t
 ), runs as (select b.*,sum(boundary) over(order by ts) run from boundaries b),
 blocks as (
  select min(ts) at,round(sum(elevated_seconds)/60)::integer minutes,
   round(sum(hr_weighted_sum)/nullif(sum(hr_seconds),0)) avg_hr,sum(raw) raw,run
  from runs where z>=1 group by run having sum(session_seconds)>=900
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

-- The reserve numbers themselves changed, so every stored close from bb-2.1 is an input
-- to a chain that no longer holds. Bump the version the same way bb-2.1 did: the anchor
-- predicate, the published version, and the three settle/publish gates.
do $$
declare def text; patched text; target text;
begin
 foreach target in array array['nb.reserve_anchor_info(uuid,date)','nb.compute_reserve(uuid,date)',
   'nb.settle_day(uuid,date)','nb.recompute_range(uuid,date,date,text)','public.calculation_status(date,date)'] loop
  def:=pg_get_functiondef(target::regprocedure);
  patched:=replace(def,'bb-2.1','bb-2.2');
  if def=patched then raise exception 'BB22_VERSION_PATCH_MISSING: %',target; end if;
  execute patched;
 end loop;
end $$;

-- Input changes must invalidate the whole carry-forward chain, including archived
-- history. The existing recovery workflow hydrates old raw facts before replaying it.
insert into nb.calculation_work(user_id,dirty_from)
select user_id,min(user_day) from public.daily_results group by user_id
on conflict(user_id) do update set input_revision=nb.calculation_work.input_revision+1,
 dirty_from=least(nb.calculation_work.dirty_from,excluded.dirty_from);

revoke all on function nb.training_load_ticks(uuid,date),nb.compute_segments(uuid,date),
 nb.reserve_replay_uncached(uuid,date) from public,anon,authenticated;
