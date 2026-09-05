-- Daily pressure includes ordinary movement. No synthetic health readings are written.
-- MET is preferred; when absent, 100 steps/min approximates moderate walking (3 MET).
-- This is an energy/load estimate, not a measured MET or a clinical score.
create function nb.activity_met(p_met numeric,p_steps integer) returns numeric
language sql immutable set search_path='' as $$
 select case when p_met between 0.5 and 25 then p_met
             when p_steps >= 0 then 1 + 2 * least(2,p_steps / 500.0)
             else null end;
$$;

-- One contribution stream drives the ring, curve and source breakdown.
-- HR zones require a personal resting baseline; movement remains usable at cold start.
-- Choose the larger signal per tick so the same walk is not counted twice.
create function nb.activity_ticks(p_user uuid,p_user_day date)
returns table(ts timestamptz,heart smallint,steps integer,z smallint,raw numeric)
language sql stable set search_path='' as $$
 with profile as (
   select p.timezone,nb.hr_max(p.birth_date) as maximum,
          nb.hr_rest(p_user,p_user_day,p.timezone) as resting
   from nb.calculation_profile(p_user,p_user_day) p
 ), points as (
   select s.*,case when p.maximum>p.resting and s.heart>0
     then nb.zone_of(least(1,greatest(0,(s.heart-p.resting)/(p.maximum-p.resting))))
     else null end as zone,
     nb.activity_met(s.met,s.step) as movement_met
   from profile p cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b
   join public.raw_samples s on s.user_id=p_user and s.ts>=b.starts_at and s.ts<b.ends_at
   where s.ts<=nb.calculation_instant(p_user,p_user_day)
 ), weighted as (
   select p.*,greatest(coalesce(nb.zone_weight(p.zone)*5,0),
     coalesce(greatest(0,p.movement_met-1)*0.375,0)) as contribution
   from points p
   where p.zone is not null or p.movement_met is not null
 )
 select w.ts,w.heart,w.step,w.zone,w.contribution from weighted w;
$$;

create or replace function nb.compute_training(p_user uuid,p_user_day date)
returns table(training_load numeric,zone_minutes smallint[],peak_hr smallint,coverage numeric,curve jsonb)
language sql stable set search_path='' as $$
 with ticks as (select * from nb.activity_ticks(p_user,p_user_day)),
 cumulative as (select t.ts,sum(t.raw) over(order by t.ts) as running from ticks t)
 select case when count(*)=0 then null else least(20.9,round(21*(1-exp(-sum(t.raw)/60)),1)) end,
 array[count(*) filter(where z=1)*5,count(*) filter(where z=2)*5,
       count(*) filter(where z=3)*5,count(*) filter(where z=4)*5,
       count(*) filter(where z=5)*5]::smallint[],
 max(t.heart),round(count(*)::numeric/288,2),
 coalesce((select jsonb_agg(jsonb_build_array(extract(epoch from c.ts)::bigint,
     least(20.9,round(21*(1-exp(-c.running/60)),1))) order by c.ts) from cumulative c),'[]'::jsonb)
 from ticks t;
$$;

-- Split contiguous elevated-HR blocks from ordinary movement; short blocks remain in
-- the all-day row. Differences of rounded cumulative shares keep all rows nonnegative
-- and guarantee that even an all-exercise day reconciles exactly with the ring.
create or replace function nb.compute_segments(p_user uuid,p_user_day date)
returns jsonb language sql stable set search_path='' as $$
 with ticks as (select * from nb.activity_ticks(p_user,p_user_day)),
 boundaries as (
   select t.*,case when coalesce(t.z,0)>=1 and coalesce(lag(t.z) over(order by t.ts),0)>=1
     and t.ts-lag(t.ts) over(order by t.ts)<=interval '5 minutes' then 0 else 1 end as boundary
   from ticks t
 ), runs as (
   select b.*,sum(boundary) over(order by ts) as run from boundaries b
 ), blocks as (
   select min(ts) as at,count(*)*5 as minutes,round(avg(heart)) as avg_hr,max(z) as peak_z,
     sum(raw) as raw,run from runs where z>=1 group by run having count(*)>=3
 ), total as (
   select sum(raw) as raw,least(20.9,round(21*(1-exp(-sum(raw)/60)),1)) as load from ticks
 ), ordinary as (
   select min(r.ts) as at,sum(r.steps)::integer as steps,sum(r.raw) as raw
   from runs r where not exists(select 1 from blocks b where b.run=r.run)
 ), rows as (
   select b.at,b.minutes,b.avg_hr,b.raw,
     case when b.peak_z>=4 then 'HARD SESSION' when b.peak_z=3 then 'MODERATE BLOCK'
       else 'ELEVATED HR' end as name,null::integer as steps,false as all_day
   from blocks b
   union all
   select o.at,null,null,o.raw,'STEPS & MOVEMENT',o.steps,true from ordinary o where o.at is not null
 ), cumulative as (
   select r.*,sum(r.raw) over(order by r.at) as running from rows r
 ), allocated as (
   select c.at,c.minutes,c.avg_hr,
     coalesce(round(t.load*c.running/nullif(t.raw,0),1)
       - round(t.load*(c.running-c.raw)/nullif(t.raw,0),1),0) as delta,
     c.name,c.steps,c.all_day from cumulative c cross join total t
 )
 select coalesce(jsonb_agg(to_jsonb(a) order by a.at),'[]'::jsonb) from allocated a;
$$;

create or replace function nb.fuel_components(p_user uuid,p_user_day date)
returns table(bmr_kcal integer,active_kcal integer,bmr_full integer)
language plpgsql stable set search_path='' as $$
declare
 v_tz text; v_lo timestamptz; v_hi timestamptz; v_asof timestamptz;
 v_weight numeric; v_height numeric; v_age numeric; v_sex text;
 v_bmr numeric; v_active numeric; v_elapsed numeric;
begin
 select p.timezone,p.height_cm,p.sex,extract(year from age(p_user_day::timestamp,p.birth_date::timestamp))
 into v_tz,v_height,v_sex,v_age from nb.calculation_profile(p_user,p_user_day) p;
 if v_tz is null then return; end if;
 select starts_at,ends_at into v_lo,v_hi from nb.user_day_bounds(p_user_day,v_tz);
 v_asof:=nb.calculation_instant(p_user,p_user_day);
 -- Prefer the day's opening weight; first-time users can use their first same-day
 -- measurement once received. Future and later-day weigh-ins never backfill this day.
 select w.weight_kg into v_weight from public.weigh_ins w
 where w.user_id=p_user and w.measured_at<=v_asof and w.measured_at<v_hi
 order by (w.measured_at<v_lo) desc,
   case when w.measured_at<v_lo then w.measured_at end desc,w.measured_at asc limit 1;
 if v_weight is not null and v_height is not null and v_age is not null and v_sex is not null then
   v_bmr:=10*v_weight+6.25*v_height-5*v_age+case when v_sex='male' then 5 else -161 end;
 end if;
 select sum(greatest(0,nb.activity_met(s.met,s.step)-1)*(21::numeric/20)*v_weight*(1::numeric/12))
 into v_active from public.raw_samples s where s.user_id=p_user and s.ts>=v_lo and s.ts<v_hi
   and s.ts<=v_asof and nb.activity_met(s.met,s.step) is not null;
 v_elapsed:=least(1440,greatest(0,extract(epoch from(v_asof-v_lo))/60));
 return query select round(v_bmr*v_elapsed/1440)::integer,round(v_active)::integer,round(v_bmr)::integer;
end;
$$;

-- Preserve meal and macro rules while using the exact same energy components as the UI.
do $$ declare definition text; begin
 definition:=pg_get_functiondef('nb.compute_fuel(uuid,date)'::regprocedure);
 definition:=replace(definition,'w.measured_at < v_lo','w.measured_at <= nb.calculation_instant(p_user,p_user_day) and w.measured_at < v_hi');
 definition:=replace(definition,'order by w.measured_at desc limit 1;',
 'order by (w.measured_at < v_lo) desc, case when w.measured_at < v_lo then w.measured_at end desc, w.measured_at asc limit 1;');
 definition:=replace(definition,'v_age is null then','v_age is null or v_sex is null then');
 definition:=replace(definition,'v_out := round(v_bmr * v_elapsed / 1440 + v_active)::integer;',
 'select c.bmr_kcal + c.active_kcal into v_out from nb.fuel_components(p_user,p_user_day) c;');
 execute definition;
end $$;

revoke all on function nb.activity_met(numeric,integer) from public,anon,authenticated;
revoke all on function nb.activity_ticks(uuid,date) from public,anon,authenticated;
-- Existing result caches must be recalculated on the next sync, including historical days.
select nb.invalidate_calculation(user_id,min(user_day)) from public.daily_results group by user_id;
