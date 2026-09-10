begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(15);

-- #28 · one night the band filed from 22:00 to 07:00, with a stage line that says where
-- every minute of it went. The user says the first ninety minutes were reading, not sleep.
insert into auth.users(id) values ('28280000-0000-4000-8000-000000000001');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date,goal)
 values ('28280000-0000-4000-8000-000000000001','UTC','male',180,'1990-01-01','RECOMP');
insert into public.consents(user_id,consent_version,choice,decided_at,text_sha256,locale)
 values ('28280000-0000-4000-8000-000000000001','v1','granted','2026-09-01 00:00+00','sha','zh-CN');
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,wake_count,
  sleep_start,wake_at,raw)
values ('28280000-0000-4000-8000-000000000001','2026-09-15',520,120,330,1,
 '2026-09-14 22:00+00','2026-09-15 07:00+00',
 jsonb_build_object('line', jsonb_build_array(
   jsonb_build_object('stage',1,'minutes',90,'offset_minutes',0),
   jsonb_build_object('stage',0,'minutes',120,'offset_minutes',90),
   jsonb_build_object('stage',1,'minutes',60,'offset_minutes',210),
   jsonb_build_object('stage',4,'minutes',20,'offset_minutes',270),
   jsonb_build_object('stage',2,'minutes',70,'offset_minutes',290),
   jsonb_build_object('stage',1,'minutes',180,'offset_minutes',360))));

select set_config('nb.calculation_as_of','2026-09-15 12:00+00',true);
select set_config('nb.calculation_day','2026-09-15',true);
select set_config('request.jwt.claim.sub','28280000-0000-4000-8000-000000000001',true);

select is((select count(*)::int from nb.sleep_evidence_minutes('28280000-0000-4000-8000-000000000001','2026-09-15')),
  540, 'the band own window carries every minute it recorded');

select lives_ok($$select public.correct_sleep_window('2026-09-15','23:30','07:00')$$,
  'a night that exists can be corrected');

-- The published window is the user's; the band's is kept, not overwritten.
select results_eq($$select sleep_start,wake_at,corrected_at is not null
  from public.sleep_nights where user_day='2026-09-15'$$,
  $$values (timestamptz '2026-09-14 23:30+00', timestamptz '2026-09-15 07:00+00', true)$$,
  'the corrected window is what the row publishes');
select is((select nb.bb_instant(raw->>'recorded_start') from public.sleep_nights where user_day='2026-09-15'),
  timestamptz '2026-09-14 22:00+00', 'the band own start is filed beside it, not lost');

-- The window moves. The stage line does not: every minute keeps the clock time it was
-- recorded at, so a correction can only ever clip.
select is((select count(*)::int from nb.sleep_evidence_minutes('28280000-0000-4000-8000-000000000001','2026-09-15')),
  450, 'the corrected window carries only the minutes inside it');
select is((select m.stage from nb.sleep_evidence_minutes('28280000-0000-4000-8000-000000000001','2026-09-15') m
  where m.ts='2026-09-15 00:00+00'), 0, 'a deep minute at midnight is still deep at midnight');
select is((select count(*)::int from nb.sleep_evidence_minutes('28280000-0000-4000-8000-000000000001','2026-09-15') m
  where m.ts<'2026-09-14 23:30+00'), 0, 'nothing before the corrected start survives');

select results_eq($$select total_minutes,deep_minutes,light_minutes,rem_minutes,wake_count
  from nb.corrected_night_totals('28280000-0000-4000-8000-000000000001','2026-09-15')$$,
  $$values (430::smallint,120::smallint,240::smallint,70::smallint,1::smallint)$$,
  'the night is re-counted over the window the user asserted');

select is((select (p.inputs->>'duration_min')::int from nb.night_score_parts('28280000-0000-4000-8000-000000000001','2026-09-15') p),
  430, 'the sleep score reads the corrected duration');
-- The row the phone selects has to say the same thing the score does.
select results_eq($$select total_minutes,deep_minutes,light_minutes,wake_count
  from public.sleep_nights where user_day='2026-09-15'$$,
  $$values (430::smallint,120::smallint,240::smallint,1::smallint)$$,
  'the published row is re-counted with the window');
select is((select p.inputs->>'duration_basis' from nb.night_score_parts('28280000-0000-4000-8000-000000000001','2026-09-15') p),
  'user_corrected', 'and says so on the page that prints it');

-- ⚠️ The reverse of the reported failure: the next sync brings the band's window back and
-- must not quietly take the night with it.
update public.sleep_nights set sleep_start='2026-09-14 21:40+00', wake_at='2026-09-15 07:00+00',
  total_minutes=545 where user_day='2026-09-15';
select results_eq($$select sleep_start,nb.bb_instant(raw->>'recorded_start')
  from public.sleep_nights where user_day='2026-09-15'$$,
  $$values (timestamptz '2026-09-14 23:30+00', timestamptz '2026-09-14 21:40+00')$$,
  'a later sync refreshes the band window and leaves the correction standing');

-- A window with no recorded sleep in it is not a night. It is refused, and the row it
-- would have replaced is left exactly as it was.
select throws_ok($$select public.correct_sleep_window('2026-09-15','07:00','07:30')$$,
  '22023', 'WINDOW_HAS_NO_SLEEP', 'a window holding no recorded sleep cannot be published');

select lives_ok($$select public.clear_sleep_correction('2026-09-15')$$,
  'the correction can be cleared');
select results_eq($$select sleep_start,wake_at,total_minutes,raw ? 'recorded_start'
  from public.sleep_nights where user_day='2026-09-15'$$,
  $$values (timestamptz '2026-09-14 21:40+00', timestamptz '2026-09-15 07:00+00', 545::smallint, false)$$,
  'clearing gives the band its window and its totals back');

select * from finish();
rollback;
