-- 13 rule 09 · 「the morning widget once a day, bb_morning_shown_at on the 04:00 day, written to
-- the cloud」. The stamp lives on the day row so a reinstall cannot show the same morning twice.
alter table public.daily_results add column if not exists bb_morning_shown_at timestamptz;
