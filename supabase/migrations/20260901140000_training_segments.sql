-- 08 · TODAY'S BUILD. The board lists four rows that add up to the number on the ring,
-- and the whole point of the card is that the number can be taken apart. So the rows have
-- to be derived, not narrated: contiguous runs of elevated ticks, plus one all-day row for
-- everything that never rose out of Z1.
--
-- ⚠️ The deltas are allocated proportionally out of the day's total, not computed per
-- segment in isolation. TRAINING_LOAD is 21·(1−e^(−RAW/60)), which is concave: four
-- separately transformed segments sum to more than the day's total and the card would then
-- contradict the ring directly above it. Each row gets its share of the raw work, so the
-- column adds up to the number on the ring by construction.

alter table public.daily_training
  add column if not exists segments jsonb not null default '[]'::jsonb;

create or replace function nb.compute_segments(p_user uuid, p_user_day date)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz   text;
  v_birth date;
  v_max  numeric;
  v_rest numeric;
  v_lo   timestamptz;
  v_hi   timestamptz;
  v_out  jsonb;
begin
  select timezone, birth_date into v_tz, v_birth from public.profiles where user_id = p_user;
  if v_tz is null then return '[]'::jsonb; end if;
  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);
  v_max := nb.hr_max(v_birth);
  v_rest := nb.hr_rest(p_user, p_user_day, v_tz);
  if v_max is null or v_rest is null or v_max <= v_rest then return '[]'::jsonb; end if;

  with pts as (
    select rs.ts, rs.heart, coalesce(rs.step, 0) as step, coalesce(rs.dis, 0) as dis,
           nb.zone_of(least(1, greatest(0, (rs.heart - v_rest) / (v_max - v_rest)))) as z
    from public.raw_samples rs
    where rs.user_id = p_user and rs.ts >= v_lo and rs.ts < v_hi
      and rs.heart is not null and rs.ts <= now()
  ),
  marked as (
    -- ⚠️ Elevated is "above resting", not "above Z2", and it is smoothed across three
    -- ticks. A half-hour walk sits right on the Z1/Z2 line and alternates across it every
    -- five minutes; testing a single tick shatters one walk into six runs of one, all of
    -- them below the minimum length, and the card loses the walk entirely.
    select p.*,
           nb.zone_weight(p.z) as w,
           case when max(p.z) over (order by p.ts rows between 1 preceding and 1 following) >= 1
                then 1 else 0 end as elevated
    from pts p
  ),
  runs as (
    -- Gaps and islands: a contiguous run shares one key, because the overall row number
    -- and the per-state row number drift apart only where the state changes.
    select m.*,
           row_number() over (order by m.ts)
             - row_number() over (partition by m.elevated order by m.ts) as run_key
    from marked m
  ),
  total as (
    select coalesce(sum(r.w * 5), 0) as raw,
           least(20.9, round((21 * (1 - exp(-coalesce(sum(r.w * 5), 0) / 60.0)))::numeric, 1)) as load
    from runs r
  ),
  agg as (
    select
      min(r.ts) as at, count(*) * 5 as minutes,
      round(avg(r.heart)) as avg_hr, max(r.z) as peak_z,
      sum(r.w * 5) as raw, r.elevated
    from runs r
    group by r.elevated, r.run_key
    having r.elevated = 1 and count(*) >= 3   -- 15 minutes is the shortest thing worth a row
  ),
  quiet as (
    select coalesce(sum(r.step), 0) as steps, coalesce(sum(r.dis), 0) as dis,
           coalesce(sum(r.w * 5), 0) as raw
    from runs r where r.elevated = 0
  )
  select coalesce(jsonb_agg(x order by x.at), '[]'::jsonb) into v_out from (
    select a.at, a.minutes, a.avg_hr,
           round((t.load * a.raw / nullif(t.raw, 0))::numeric, 1) as delta,
           case when a.peak_z >= 4 then 'HARD SESSION'
                when a.peak_z = 3 then 'MODERATE BLOCK'
                else 'ELEVATED HR' end as name,
           null::integer as steps, false as all_day
    from agg a, total t
    union all
    select v_lo, null, null,
           round((t.load * q.raw / nullif(t.raw, 0))::numeric, 1),
           'STEPS & MOVEMENT', q.steps::integer, true
    from quiet q, total t where q.steps > 0
  ) x;

  return coalesce(v_out, '[]'::jsonb);
end;
$$;

-- A BEFORE trigger, not an AFTER one: the rows are written straight into NEW rather than
-- issued as a second UPDATE, which would re-enter this trigger. It also means a day that
-- re-settles gets its rows recomputed instead of keeping the first set it ever had.
create or replace function nb.on_training_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_day date;
begin
  select dr.user_day into v_day from public.daily_results dr where dr.id = new.result_id;
  if v_day is not null then
    new.segments := nb.compute_segments(new.user_id, v_day);
  end if;
  return new;
end;
$$;

drop trigger if exists daily_training_segments on public.daily_training;
create trigger daily_training_segments
before insert or update on public.daily_training
for each row execute function nb.on_training_settled();
