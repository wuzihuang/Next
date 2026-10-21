begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();

insert into auth.users(id) values ('20261021-0000-4000-8000-000000000001');
insert into public.profiles(user_id,timezone,birth_date) values
 ('20261021-0000-4000-8000-000000000001','UTC','1990-01-01');
insert into public.consents(user_id,consent_version,choice,decided_at,text_sha256,locale)
values ('20261021-0000-4000-8000-000000000001','v1','granted','2026-09-01','test','en');
select set_config('nb.calculation_as_of','2026-10-20 12:00+00',true);
select set_config('nb.calculation_day','2026-10-20',true);
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,
 light_minutes,wake_count,sleep_start,wake_at,sleep_line)
values ('20261021-0000-4000-8000-000000000001','2026-10-20',480,90,270,1,
 '2026-10-19 22:30+00','2026-10-20 06:30+00','0:90,1:150,4:30,1:120,2:90');

select nb.refresh_night_score('20261021-0000-4000-8000-000000000001','2026-10-20');
select is((select score_version from public.night_score where user_id='20261021-0000-4000-8000-000000000001'),
 'sleep-v3.0','seven-contributor scoring has its own version');
select is((select (inputs->>'duration_min')::numeric from public.night_score where user_id='20261021-0000-4000-8000-000000000001'),
 450::numeric,'total sleep excludes awake minutes');
select is((select (inputs->>'efficiency_pct')::numeric from public.night_score where user_id='20261021-0000-4000-8000-000000000001'),
 93.75::numeric,'efficiency is explicitly measured within the recorded interval');
select ok((select not(inputs ? 'score_latency') and not(inputs ? 'latency_min')
 from public.night_score where user_id='20261021-0000-4000-8000-000000000001'),
 'no bedtime evidence means no invented latency');
select ok((select architecture_score is null and recovery_score is null and regularity_score is null
 from public.night_score where user_id='20261021-0000-4000-8000-000000000001'),
 'retired groups are not reused as misleading new contributors');
select is((select (inputs->>'midpoint_min')::numeric from public.night_score where user_id='20261021-0000-4000-8000-000000000001'),
 150::numeric,'timing uses local sleep midpoint across midnight');
select is((nb.training_recovery_target('20261021-0000-4000-8000-000000000001','2026-10-20',70::smallint)->>'readiness')::numeric,
 (select round(score*0.8+70*0.2,1) from public.night_score where user_id='20261021-0000-4000-8000-000000000001'),
 'training uses the final seven-factor score rather than reweighting retired groups');
select is(nb.training_recovery_target('20261021-0000-4000-8000-000000000001','2026-10-20',70::smallint)->>'version',
 'target-1.1','the downstream scoring change is versioned');

select is(nb.sleep_contributor_value('rem',59),59::numeric/90*100,'REM uses absolute minutes, not a flattering short-night percentage');
select is(nb.sleep_contributor_value('deep',66),100::numeric,'an hour of deep sleep meets the product target');
select is(nb.sleep_contributor_value('latency',15),100::numeric,'15-minute latency is optimal');
select is(nb.sleep_contributor_value('latency',20),100::numeric,'20-minute latency is optimal');
select ok(nb.sleep_contributor_value('latency',2)<nb.sleep_contributor_value('latency',15),
 'falling asleep immediately is not automatically optimal');
select is(nb.sleep_contributor_value('timing',0),100::numeric,'midnight midpoint is optimal');
select is(nb.sleep_contributor_value('timing',180),100::numeric,'03:00 midpoint is optimal');
select is(nb.sleep_contributor_value('timing',1439),nb.sleep_contributor_value('timing',181),
 'timing uses circular clock distance');
select is(nb.sleep_contributor_value('timing',720),0::numeric,'regular daytime sleep is not mistaken for ideal circadian alignment');
select is(nb.sleep_contributor_value('efficiency',85),100::numeric,'85 percent recorded efficiency meets the reference');
select is(nb.sleep_contributor_value('rem',null),null::numeric,'missing input stays missing');
select is(nb.sleep_contributor_value('rem',-1),null::numeric,'invalid negative input stays missing');

create temporary table before_physiology as
 select score,inputs from nb.night_score_parts('20261021-0000-4000-8000-000000000001','2026-10-20');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv) values
 ('20261021-0000-4000-8000-000000000001','2026-10-19 23:15+00','UTC',100,1),
 ('20261021-0000-4000-8000-000000000001','2026-10-19 23:30+00','UTC',100,1);
select is((select score from nb.night_score_parts('20261021-0000-4000-8000-000000000001','2026-10-20')),
 (select score from before_physiology),'HRV and resting heart rate no longer change sleep score');

update public.sleep_nights set total_minutes=325,deep_minutes=66,light_minutes=164,
 wake_at='2026-10-20 03:55+00',sleep_line='0:66,1:100,4:36,1:64,2:59'
where user_id='20261021-0000-4000-8000-000000000001';
select ok((select (inputs->>'duration_min')::numeric=289 and score<=56
 and (inputs->>'score_rem')::numeric<70 and (inputs->>'duration_cap_applied')::numeric=1
 from nb.night_score_parts('20261021-0000-4000-8000-000000000001','2026-10-20')),
 'screenshot-shaped short sleep cannot become a high score from good stage percentages');

update public.sleep_nights set total_minutes=480,deep_minutes=90,light_minutes=390,
 wake_at='2026-10-20 06:30+00',sleep_line='0:90,1:390'
where user_id='20261021-0000-4000-8000-000000000001';
select ok((select not(inputs ? 'score_rem') and not(inputs ? 'rem_min')
 from nb.night_score_parts('20261021-0000-4000-8000-000000000001','2026-10-20')),
 'ordinary two-stage nights do not invent measured zero REM');
update public.sleep_nights set sleep_line='0:90,1:120,4:30,1:120,2:60'
where user_id='20261021-0000-4000-8000-000000000001';
select ok((select not(inputs ? 'efficiency_pct') and not(inputs ? 'score_restfulness')
 and (inputs->>'unstaged_minutes')::numeric=60
 from nb.night_score_parts('20261021-0000-4000-8000-000000000001','2026-10-20')),
 'partial coverage cannot fabricate efficiency or uninterrupted rest');
update public.sleep_nights set sleep_line=null,deep_minutes=null,light_minutes=null,wake_count=null
where user_id='20261021-0000-4000-8000-000000000001';
select ok((select not(inputs ? 'score_deep') and not(inputs ? 'score_restfulness')
 and not(inputs ? 'score_efficiency') and (inputs->>'duration_recorded')::numeric=0
 from nb.night_score_parts('20261021-0000-4000-8000-000000000001','2026-10-20')),
 'aggregate-only nights retain an explicitly estimated duration, not fabricated stages');
select is((select count(*) from nb.night_score_parts('20261021-0000-4000-8000-000000000001','2026-10-19')),
 0::bigint,'missing nights have no score');

update public.sleep_nights set total_minutes=480,deep_minutes=90,light_minutes=270,
 sleep_line='0:90,1:150,4:30,1:120,2:90'
where user_id='20261021-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','20261021-0000-4000-8000-000000000001',true);
select lives_ok($$select public.correct_sleep_window('2026-10-20','22:30','02:30')$$,
 'sleep corrections remain supported');
select ok((select (inputs->>'duration_min')::numeric=240 and score<=40
 from nb.night_score_parts('20261021-0000-4000-8000-000000000001','2026-10-20')),
 'corrected windows are clipped before scoring');
select lives_ok($$select public.clear_sleep_correction('2026-10-20')$$,'clearing restores the measured window');
update public.sleep_nights set total_minutes=480,deep_minutes=90,light_minutes=270,
 sleep_line='0:90,1:150,3:30,1:120,2:90'
where user_id='20261021-0000-4000-8000-000000000001';
select is((select (inputs->>'duration_min')::numeric from nb.night_score_parts(
 '20261021-0000-4000-8000-000000000001','2026-10-20')),450::numeric,
 'insomnia stage is awake, not sleep');
insert into auth.users(id) values ('20261021-0000-4000-8000-000000000002');
insert into public.profiles(user_id,timezone,birth_date) values
 ('20261021-0000-4000-8000-000000000002','Asia/Shanghai','1990-01-01');
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,
 light_minutes,wake_count,sleep_start,wake_at,sleep_line)
select '20261021-0000-4000-8000-000000000002',user_day,total_minutes,deep_minutes,
 light_minutes,wake_count,sleep_start,wake_at,sleep_line from public.sleep_nights
where user_id='20261021-0000-4000-8000-000000000001';
select is((select (inputs->>'midpoint_min')::numeric from nb.night_score_parts(
 '20261021-0000-4000-8000-000000000002','2026-10-20')),630::numeric,
 'timing uses the wearer timezone, not the database timezone');
update public.sleep_nights set total_minutes=360,deep_minutes=60,light_minutes=240,
 sleep_start='2026-10-19 23:00+00',wake_at='2026-10-20 07:00+00',sleep_line=null,
 raw='{"intervals":[{"start":"2026-10-19T23:00:00Z","end":"2026-10-20T01:00:00Z"},
 {"start":"2026-10-20T03:00:00Z","end":"2026-10-20T07:00:00Z"}],
 "line":[{"stage":0,"minutes":60,"offset_minutes":0},
 {"stage":1,"minutes":60,"offset_minutes":60},
 {"stage":1,"minutes":180,"offset_minutes":240},
 {"stage":2,"minutes":60,"offset_minutes":420}]}'::jsonb
where user_id='20261021-0000-4000-8000-000000000001';
select ok((select (inputs->>'duration_min')::numeric=360
 and (inputs->>'sleep_gap_minutes')::numeric=120 and (inputs->>'midpoint_min')::numeric=300
 from nb.night_score_parts('20261021-0000-4000-8000-000000000001','2026-10-20')),
 'split records preserve gaps and timing uses the longest actual segment');
select is((select count(*) from nb.night_score_parts('20261021-0000-4000-8000-000000000003','2026-10-20')),
 0::bigint,'another account cannot supply this night evidence');
select ok(bool_and(nb.sleep_contributor_value(kind,m) between 0 and 100),
 'all supported contributor curves stay bounded')
from unnest(array['total_sleep','restfulness','rem','deep','latency','timing']) kind
cross join generate_series(0,1439) m;
select ok(bool_and(nb.sleep_duration_score_cap(m)>=nb.sleep_duration_score_cap(m-1)
 and nb.sleep_duration_score_cap(m)-nb.sleep_duration_score_cap(m-1)<=1),
 'the short-sleep ceiling remains continuous and monotonic')
from generate_series(1,720) m;
update public.sleep_nights set total_minutes=0
where user_id='20261021-0000-4000-8000-000000000001';
select nb.refresh_night_score('20261021-0000-4000-8000-000000000001','2026-10-20');
select is((select count(*) from public.night_score where user_id='20261021-0000-4000-8000-000000000001'),
 0::bigint,'invalidated sleep cannot leave an old score behind');
select ok(not has_function_privilege('authenticated','nb.sleep_contributor_value(text,numeric)','execute')
 and not has_function_privilege('anon','nb.night_score_parts(uuid,date)','execute'),
 'internal scoring retains private privileges');
select * from finish();
rollback;
