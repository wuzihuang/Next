-- Issue #19 · one calendar, and it starts where the clock does.
--
-- F2 rule 03 has read "the user day runs local 04:00 → 04:00" since the first schema. The
-- seam was there so a night that ends at 02:40 still closes the day it belongs to, but the
-- product never spoke that seam out loud: the cards say TODAY, the person reads midnight,
-- and between 00:00 and 04:00 every accumulated number on the screen was still yesterday's.
-- The rolling instruments made it worse — HEART and RESPONSE drew a rolling 24 hours while
-- STEPS and FUEL drew 04:00→now, so two cards on the same screen answered "today" with two
-- different windows.
--
-- The user day is now local 00:00 → 00:00. Sleep is unaffected: a night is keyed to the
-- calendar day the person woke on (`sleep_nights.user_day`) and is stored, not derived, so
-- nothing about last night moves. What moves is every accumulated day number, which is why
-- this migration also marks every account dirty from its first recorded day: the stored
-- results were cut on the old seam and must be replayed before they can be read again.
--
-- ⚠️ Meals and weigh-ins logged between 00:00 and 04:00 before this migration were filed by
-- the phone under the previous calendar day and stay there. They are stored facts with
-- their own `user_day`, not derived ones, so replay keeps them where they were written;
-- only entries made from now on land on the day the clock shows.

-- ---------------------------------------------------------------- the calendar

create or replace function nb.user_day_bounds(p_user_day date, p_tz text)
returns table (starts_at timestamptz, ends_at timestamptz)
language sql
immutable
set search_path = ''
as $$
  select ((p_user_day + time '00:00') at time zone p_tz),
         ((p_user_day + 1 + time '00:00') at time zone p_tz);
$$;

create or replace function nb.user_day_of(p_ts timestamptz, p_tz text)
returns date
language sql
immutable
set search_path = ''
as $$
  select ((p_ts at time zone p_tz)::date);
$$;

comment on function nb.user_day_bounds(date, text) is
  'F2 rule 03 · one calendar. The user day runs local 00:00 -> 00:00.';

-- ---------------------------------------------------------------- the one open-coded copy

-- `public.ingest_band_domain` decides which day a written tick dirties, and it open-coded
-- the seam instead of calling nb.user_day_of. Left alone it would file every 00:00-04:00
-- tick against yesterday and leave today unsettled. Anchored replacement rather than a
-- fresh copy: the function is edited by several other migrations and must keep whatever
-- body it currently carries.
do $$
declare def text; patched text;
begin
  select pg_get_functiondef(oid) into def from pg_proc
   where pronamespace = 'public'::regnamespace and proname = 'ingest_band_domain';
  if def is null then raise exception 'USER_DAY_MIDNIGHT_INGEST_MISSING'; end if;
  patched := replace(def,
    '((t at time zone coalesce(old.sampled_tz,p_timezone))-interval ''4 hours'')::date',
    'nb.user_day_of(t,coalesce(old.sampled_tz,p_timezone))');
  if patched = def then
    -- Already on nb.user_day_of, or the expression was reshaped by a later migration.
    if position('nb.user_day_of(t,coalesce(old.sampled_tz,p_timezone))' in def) = 0 then
      raise exception 'USER_DAY_MIDNIGHT_INGEST_ANCHOR_MISSING';
    end if;
  else
    execute patched;
  end if;
end $$;

-- ---------------------------------------------------------------- replay the old seam out

-- Every stored daily_results row was integrated between the old 04:00 bounds, so every one
-- of them is now wrong by the four hours at each end. Marking the account dirty from its
-- first recorded day is the house mechanism: nb.recompute_range replays the chain in order,
-- carry-forward included, the next time the cron or settle_now comes round, and
-- public.calculation_status reports those days pending until it has.
--
-- The 385-day guard in nb.recompute_range refuses a dirty_from older than that, so the
-- floor is applied here rather than leaving an account permanently unable to replay.
insert into nb.calculation_work (user_id, dirty_from)
select r.user_id, greatest(min(r.user_day), current_date - 380)
from public.daily_results r
group by r.user_id
on conflict (user_id) do update set
  input_revision = nb.calculation_work.input_revision + 1,
  dirty_from = least(coalesce(nb.calculation_work.dirty_from, excluded.dirty_from),
                     excluded.dirty_from);

-- Nights are keyed to the day the person woke and did not move, but the score reads its
-- baselines through nb.calculation_profile on a user day, so it is refreshed with the same
-- pass rather than left holding a value computed against the old bounds.
do $$
declare r record;
begin
  for r in select sn.user_id, sn.user_day from public.sleep_nights sn
           where coalesce(sn.total_minutes, 0) > 0
           order by sn.user_id, sn.user_day loop
    perform nb.refresh_night_score(r.user_id, r.user_day);
  end loop;
end $$;
