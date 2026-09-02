-- Step B. Apply only after every client is on a build that no longer writes these.
--
-- F7 rule 09 · 「raw 表不许有任何日期列」. calendar_day was the device's local day, written
-- at ingest and read by nothing — a second calendar on the one table F0 law 04 says has
-- exactly one, re-cut at settle from ts + sampled_tz.
-- F2 · dayOffset 降级成 SDK 的分页参数，永不出现在 UI、结算与表键里. Stored on every row,
-- read by nothing.
-- F5 §07 / F7 §03 · blood oxygen is DROP: 数值不上屏、不入库、不喂 AI. Not stored means not stored.
alter table public.raw_samples
  drop column if exists spo2,
  drop column if exists calendar_day,
  drop column if exists day_offset;
