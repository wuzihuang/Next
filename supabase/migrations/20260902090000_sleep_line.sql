-- 04B rule 04 · the SLEEP strip draws the band's own sleepLine, never a re-segmentation.
-- Stored as compact "stage:minutes" runs (SDK stages: 0 deep, 1 light, 2 REM, 3 insomnia,
-- 4 awake — KH firmware emits no 2/3), e.g. "1:84,0:60,1:110,4:4". Rows from before this
-- column read as NULL and the app falls back to the totals.
alter table public.sleep_nights add column if not exists sleep_line text;
