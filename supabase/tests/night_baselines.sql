begin;
select plan(10);
insert into auth.users(id) values('09090909-0000-4000-8000-000000000045');
insert into public.profiles(user_id,timezone) values('09090909-0000-4000-8000-000000000045','UTC');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,sleep_states) values
('09090909-0000-4000-8000-000000000045','2026-09-03 23:55+00','UTC',10,0),
('09090909-0000-4000-8000-000000000045','2026-09-04 00:00+00','UTC',50,0),
('09090909-0000-4000-8000-000000000045','2026-09-04 00:05+00','UTC',70,0),
('09090909-0000-4000-8000-000000000045','2026-09-04 00:10+00','UTC',1,1),
('09090909-0000-4000-8000-000000000045','2026-09-04 05:00+00','UTC',80,1),
('09090909-0000-4000-8000-000000000045','2026-09-04 05:05+00','UTC',100,1);
select is(nb.night_rhr('09090909-0000-4000-8000-000000000045','2026-09-04','UTC'),81::numeric,'missing window uses 04-to-04 day and sleep-state filter');
insert into public.sleep_nights(user_id,user_day,total_minutes,sleep_start,wake_at) values
('09090909-0000-4000-8000-000000000045','2026-09-04',10,'2026-09-04 00:00+00','2026-09-04 00:10+00');
select is(nb.night_rhr('09090909-0000-4000-8000-000000000045','2026-09-04','UTC'),51::numeric,'window includes start, excludes wake, ignores sleep_states');
update public.sleep_nights set wake_at=null where user_id='09090909-0000-4000-8000-000000000045';
select is(nb.night_rhr('09090909-0000-4000-8000-000000000045','2026-09-04','UTC'),81::numeric,'partial window preserves fallback');
update public.sleep_nights set wake_at=sleep_start where user_id='09090909-0000-4000-8000-000000000045';
select is(nb.night_rhr('09090909-0000-4000-8000-000000000045','2026-09-04','UTC'),null::numeric,'empty known window stays missing');
select is(nb.night_rhr('09090909-0000-4000-8000-000000000046','2026-09-04','UTC'),null::numeric,'another account has no readings');
select is(nb.charge_multiplier('09090909-0000-4000-8000-000000000045','2026-09-04','UTC'),1::numeric,'insufficient baseline retains neutral multiplier');
select is(nb.night_inputs('09090909-0000-4000-8000-000000000045','2026-09-04')->>'rhr_nights','1','baseline counts measured fallback night once');
select is(nb.night_inputs('09090909-0000-4000-8000-000000000045','2026-09-04')->>'hrv_nights','0','missing HRV nights do not become zero readings');
update public.sleep_nights set wake_at='2026-09-04 00:10+00' where user_id='09090909-0000-4000-8000-000000000045';
select is(nb.night_rhr('09090909-0000-4000-8000-000000000045','2026-09-04','UTC'),51::numeric,'same transaction updated window is immediately visible');
update public.raw_samples set heart=0 where user_id='09090909-0000-4000-8000-000000000045' and ts='2026-09-04 00:00+00';
select is(nb.night_rhr('09090909-0000-4000-8000-000000000045','2026-09-04','UTC'),3.5::numeric,'existing percentile zero-heart semantics remain unchanged');
select * from finish();
rollback;
