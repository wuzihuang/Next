-- Step A of two. Old app builds still write calendar_day and day_offset on every raw row;
-- relaxing NOT NULL lets them keep working while the new build stops writing them. Step B
-- (20260902020000) drops the columns once no client writes them.
alter table public.raw_samples
  alter column calendar_day drop not null,
  alter column day_offset   drop not null;
