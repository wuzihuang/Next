-- The deployed compute_fuel retained its legacy return expression: an earlier
-- string replacement silently missed that body, while fuel_components changed.
-- Replace whole definitions so a database with either body gets one energy ledger.
-- BIA BMR stays a device estimate for comparison; the resting baseline is Mifflin.
create or replace function nb.activity_met(p_met numeric,p_steps integer) returns numeric
language sql immutable set search_path='' as $$
 select case when p_met between 0.5 and 25 then p_met
             when p_steps >= 0 then 1 + 2 * least(2,p_steps / 500.0)
             else null end;
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
 -- Sum the numerator before dividing. A rounded decimal approximation of 1/12
 -- made an exact 157.5 kcal become 157.499… and round down to 157.
 select sum(greatest(0,nb.activity_met(s.met,s.step)-1)*21*v_weight)/240
 into v_active from public.raw_samples s where s.user_id=p_user and s.ts>=v_lo and s.ts<v_hi
   and s.ts<=v_asof and nb.activity_met(s.met,s.step) is not null;
 -- A user day runs 04:00 to the next local 04:00, including 23/25-hour DST days.
 v_elapsed:=greatest(0,extract(epoch from(v_asof-v_lo)));
 return query select round(v_bmr*v_elapsed/nullif(extract(epoch from(v_hi-v_lo)),0))::integer,
   round(v_active)::integer,round(v_bmr)::integer;
end;
$$;

CREATE OR REPLACE FUNCTION nb.compute_fuel(p_user uuid, p_user_day date)
 RETURNS TABLE(intake_state text, kcal_in integer, kcal_out integer, balance integer, target_in integer, protein_g integer, fat_g integer, carb_g integer, direction text, slot_states jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_tz       text;
  v_lo       timestamptz;
  v_hi       timestamptz;
  v_weight   numeric;
  v_height   numeric;
  v_age      numeric;
  v_sex      text;
  v_goal     text;
  v_bmr      numeric;
  v_in       integer;
  v_slots    integer;
  v_coverage numeric;
  v_state    text;
  v_p        integer;
  v_f        integer;
  v_c        integer;
  v_target   numeric;
  v_out      integer;
  v_balance  integer;
begin
  select p.timezone, p.height_cm, p.sex, p.goal,
         extract(year from age(p_user_day::timestamp, p.birth_date::timestamp))
    into v_tz, v_height, v_sex, v_goal, v_age
  from nb.calculation_profile(p_user, p_user_day) p where p.user_id = p_user;
  if v_tz is null then return; end if;

  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);

  select w.weight_kg into v_weight
  from public.weigh_ins w
  where w.user_id = p_user and w.measured_at <= nb.calculation_instant(p_user,p_user_day) and w.measured_at < v_hi
  order by (w.measured_at < v_lo) desc, case when w.measured_at < v_lo then w.measured_at end desc, w.measured_at asc limit 1;

  if v_weight is null or v_height is null or v_age is null or v_sex is null then
    v_bmr := null;
  else
    v_bmr := 10 * v_weight + 6.25 * v_height - 5 * v_age
             + case when v_sex = 'male' then 5 else -161 end;
  end if;

  -- Missing movement must not be published as a complete burn or a zero.
  -- Both consumers use the very same rounded components, including step fallback.
  select c.bmr_kcal + c.active_kcal into v_out
  from nb.fuel_components(p_user,p_user_day) c;

  select count(distinct date_bin(interval '5 minutes',s.ts,v_lo))::numeric
    / nullif(extract(epoch from(v_hi-v_lo))/300,0) into v_coverage
  from public.raw_samples s
  where s.user_id = p_user and s.ts >= v_lo and s.ts < v_hi
    and s.ts <= nb.calculation_instant(p_user,p_user_day)
    and nb.activity_met(s.met,s.step) is not null;

  select sum(m.kcal), count(distinct m.slot)
    into v_in, v_slots
  from public.meals m
  where m.user_id = p_user and m.user_day = p_user_day and m.deleted_at is null
    and m.model_version is distinct from 'seed';

  v_state := case when exists(select 1 from public.fasted_days f where f.user_id=p_user and f.user_day=p_user_day) then 'FASTED'
    when v_slots is null or v_slots = 0 then 'UNLOGGED'
    when v_slots >= 4 then 'CONFIRMED'
    else 'PARTIAL'
  end;

  if v_weight is not null and v_bmr is not null then
    v_target := v_bmr * 1.35 + case v_goal
                  when 'CUT' then -600 when 'BULK' then 300 else -380 end;
    v_p := round((v_weight * case v_goal
             when 'CUT' then 2.0 when 'BULK' then 1.6 else 1.9 end) / 5) * 5;
    v_f := round((v_weight * case v_goal
             when 'BULK' then 0.9 else 0.8 end) / 5) * 5;
    v_c := greatest(100, round((v_target - 4 * v_p - 9 * v_f) / 4 / 5) * 5);
    v_target := 4 * v_p + 9 * v_f + 4 * v_c;
  end if;

  if v_state <> 'UNLOGGED' and v_out is not null then
    v_balance := coalesce(v_in, 0) - v_out;
  end if;

  return query select
    v_state,
    case when v_state = 'UNLOGGED' then null else coalesce(v_in, 0) end,
    v_out,
    v_balance,
    round(v_target)::integer, v_p, v_f, v_c,
    case
      when v_state = 'UNLOGGED' then 'GREY_NOTHING'
      when v_state = 'PARTIAL' and v_slots < 2 then 'GREY_NOTHING'
      when coalesce(v_coverage, 0) < 0.5 then 'GREY_NO_BURN'
      when v_out is null then 'GREY_NO_BURN'
      when v_balance <= -150 then 'DEFICIT'
      when v_balance >= 150 then 'SURPLUS'
      else 'LEVEL'
    end,
    coalesce((
      select jsonb_object_agg(sl.name, coalesce(st.state, 'OPEN'))
      from unnest(array['BREAKFAST', 'LUNCH', 'DINNER', 'SNACK']) as sl(name)
      left join lateral (
        select 'CONFIRMED'::text as state
        from public.meals mm
        where mm.user_id = p_user and mm.user_day = p_user_day
          and mm.slot = sl.name and mm.deleted_at is null
          and mm.model_version is distinct from 'seed'
        limit 1
      ) st on true
    ), '{}'::jsonb);
end;
$function$;

-- Keep these internal functions unavailable as arbitrary-user Data API calls.
revoke all on function nb.activity_met(numeric,integer) from public,anon,authenticated;
revoke all on function nb.fuel_components(uuid,date) from public,anon,authenticated;
revoke all on function nb.compute_fuel(uuid,date) from public,anon,authenticated;

-- Publish corrected historical totals through the normal, versioned replay path.
select nb.invalidate_calculation(user_id,min(user_day))
from public.daily_results group by user_id;
