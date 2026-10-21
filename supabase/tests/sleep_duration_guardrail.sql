begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();

insert into auth.users(id) values ('20261020-0000-4000-8000-000000000001');
insert into public.profiles(user_id,timezone,birth_date) values
 ('20261020-0000-4000-8000-000000000001','UTC','1990-01-01');
insert into public.consents(user_id,consent_version,choice,decided_at,text_sha256,locale)
values ('20261020-0000-4000-8000-000000000001','v1','granted','2026-09-01','test','en');
select set_config('nb.calculation_as_of','2026-10-19 12:00+00',true);
select set_config('nb.calculation_day','2026-10-19',true);

insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,
 light_minutes,wake_count,sleep_start,wake_at,sleep_line)
select '20261020-0000-4000-8000-000000000001',d::date,450,90,261,0,
 d-interval '1 hour',d+interval '6 hours 30 minutes','0:90,1:261,2:99'
from generate_series('2026-10-16'::timestamptz,'2026-10-18'::timestamptz,interval '1 day') d;

insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,
 light_minutes,wake_count,sleep_start,wake_at,sleep_line)
values ('20261020-0000-4000-8000-000000000001','2026-10-19',300,60,174,0,
 '2026-10-18 23:00+00','2026-10-19 04:00+00','0:60,1:174,2:66');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv) values
 ('20261020-0000-4000-8000-000000000001','2026-10-18 23:15+00','UTC',60,45),
 ('20261020-0000-4000-8000-000000000001','2026-10-18 23:30+00','UTC',60,45);

select is((select duration_score from nb.night_score_parts(
 '20261020-0000-4000-8000-000000000001','2026-10-19')),50::numeric,
 'five hours earns 50 for duration');
select results_eq($$select architecture_score,recovery_score,regularity_score
 from nb.night_score_parts('20261020-0000-4000-8000-000000000001','2026-10-19')$$,
 $$select 100::numeric,100::numeric,100::numeric$$,
 'the reproduction has full marks for all three other groups');
select is((select score from nb.night_score_parts(
 '20261020-0000-4000-8000-000000000001','2026-10-19')),60::numeric,
 'five hours cannot become 88 through good physiology and regularity');
select nb.refresh_night_score('20261020-0000-4000-8000-000000000001','2026-10-19');
select is((select score from public.night_score
 where user_id='20261020-0000-4000-8000-000000000001' and user_day='2026-10-19'),60::smallint,
 'the persisted score used by every app surface respects the duration ceiling');
select is((select score_version from public.night_score
 where user_id='20261020-0000-4000-8000-000000000001' and user_day='2026-10-19'),'sleep-v2.0',
 'the changed algorithm has its own version');
select ok((select inputs @> '{"weight_duration":50,"weight_architecture":20,"weight_recovery":20,
 "weight_regularity":10,"score_before_duration_cap":75,"duration_score_cap":60,"duration_cap_applied":1}'::jsonb
 from public.night_score
 where user_id='20261020-0000-4000-8000-000000000001' and user_day='2026-10-19'),
 'the published evidence explains both the weights and the binding cap');
select is((nb.training_target('20261020-0000-4000-8000-000000000001','2026-10-19',70::smallint)
 ->>'sleep_score')::numeric,60::numeric,'training evidence reads the same settled sleep score');

select is(nb.sleep_duration_score_cap(null),null::numeric,'unknown duration has no invented limit');
select is(nb.sleep_duration_score_cap(minutes),cap,format('%s minutes has a ceiling of %s',minutes,cap))
from (values (-1,0::numeric),(0,0),(180,30),(240,40),(270,50),(300,60),
 (330,67.5),(360,75),(390,82.5),(420,90),(435,95),(450,100),(480,100),(690,100)) v(minutes,cap);
select ok(bool_and(cap between 0 and 100 and cap>=previous and cap-previous<=1),
 'the ceiling is bounded, monotonic and continuous across every minute, including hour boundaries')
from (
 select nb.sleep_duration_score_cap(m) cap,nb.sleep_duration_score_cap(m-1) previous
 from generate_series(1,1440) m
) limits;

create function pg_temp.score_for_minutes(p_minutes int) returns numeric language plpgsql as $$
begin
 update public.sleep_nights set total_minutes=p_minutes,
  deep_minutes=round(p_minutes*0.2),light_minutes=p_minutes-round(p_minutes*0.2)-round(p_minutes*0.22),
  wake_count=0,wake_at=sleep_start+make_interval(mins=>p_minutes),
  sleep_line=format('0:%s,1:%s,2:%s',round(p_minutes*0.2),
   p_minutes-round(p_minutes*0.2)-round(p_minutes*0.22),round(p_minutes*0.22))
 where user_id='20261020-0000-4000-8000-000000000001' and user_day='2026-10-19';
 return (select score from nb.night_score_parts('20261020-0000-4000-8000-000000000001','2026-10-19'));
end $$;
select is(pg_temp.score_for_minutes(minutes),expected,
 format('%s-minute night with all other groups at 100 scores %s',minutes,expected))
from (values (60,10::numeric),(180,30),(240,40),(270,50),(299,60),(300,60),(301,60),
 (330,68),(359,75),(360,75),(361,75),(390,83),(419,90),(420,90),(421,90),
 (435,95),(449,100),(450,100),(480,100),(570,100),(600,96),(690,85)) v(minutes,expected);

select is(pg_temp.score_for_minutes(300),60::numeric,'restore the five-hour case');
update public.raw_samples set heart=null,hrv=null
where user_id='20261020-0000-4000-8000-000000000001';
select results_eq($$select score,recovery_score from nb.night_score_parts(
 '20261020-0000-4000-8000-000000000001','2026-10-19')$$,
 $$select 60::numeric,null::numeric$$,'missing physiology cannot remove the duration cap');
update public.sleep_nights set total_minutes=0
where user_id='20261020-0000-4000-8000-000000000001' and user_day<'2026-10-19';
select results_eq($$select score,regularity_score from nb.night_score_parts(
 '20261020-0000-4000-8000-000000000001','2026-10-19')$$,
 $$select 60::numeric,null::numeric$$,'a new wearer without a baseline cannot bypass the cap');
update public.sleep_nights set deep_minutes=null,light_minutes=null,wake_count=null,sleep_line=null
where user_id='20261020-0000-4000-8000-000000000001' and user_day='2026-10-19';
select results_eq($$select score,architecture_score,recovery_score,regularity_score,
 (inputs->>'duration_cap_applied')::numeric from nb.night_score_parts(
 '20261020-0000-4000-8000-000000000001','2026-10-19')$$,
 $$select 50::numeric,null::numeric,null::numeric,null::numeric,0::numeric$$,
 'duration alone keeps its own score; missing groups never earn substitute marks');

update public.sleep_nights set total_minutes=450
where user_id='20261020-0000-4000-8000-000000000001' and user_day<'2026-10-19';
update public.sleep_nights set deep_minutes=0,light_minutes=300,wake_count=6,sleep_line='1:300'
where user_id='20261020-0000-4000-8000-000000000001' and user_day='2026-10-19';
update public.raw_samples set heart=100,hrv=1
where user_id='20261020-0000-4000-8000-000000000001';
select results_eq($$select score,architecture_score,recovery_score,(inputs->>'duration_cap_applied')::numeric
 from nb.night_score_parts('20261020-0000-4000-8000-000000000001','2026-10-19')$$,
 $$select 35::numeric,0::numeric,0::numeric,0::numeric$$,
 'poor structure and physiology can lower the score below the cap; the cap is not a floor');

insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,
 light_minutes,wake_count,sleep_start,wake_at,sleep_line)
select '20261020-0000-4000-8000-000000000001',d::date,300,60,174,0,
 d-interval '1 hour',d+interval '4 hours','0:60,1:174,2:66'
from generate_series('2026-09-21'::timestamptz,'2026-10-18'::timestamptz,interval '1 day') d
on conflict(user_id,user_day) do update set total_minutes=excluded.total_minutes,
 deep_minutes=excluded.deep_minutes,light_minutes=excluded.light_minutes,wake_count=excluded.wake_count,
 sleep_start=excluded.sleep_start,wake_at=excluded.wake_at,sleep_line=excluded.sleep_line;
update public.raw_samples set heart=60,hrv=45
where user_id='20261020-0000-4000-8000-000000000001';
select is(pg_temp.score_for_minutes(300),60::numeric,'a month of short nights does not normalise five hours to a high score');
select results_eq($$select duration_score,(inputs->>'baseline_bed_nights')::numeric from nb.night_score_parts(
 '20261020-0000-4000-8000-000000000001','2026-10-19')$$,
 $$select 50::numeric,28::numeric$$,'duration still uses its fixed standard after 28 valid nights');

select is((select count(*) from nb.night_score_parts(
 '20261020-0000-4000-8000-000000000001','2026-09-20')),0::bigint,'an absent night remains absent, not zero');
update public.sleep_nights set total_minutes=0
where user_id='20261020-0000-4000-8000-000000000001' and user_day='2026-10-19';
select nb.refresh_night_score('20261020-0000-4000-8000-000000000001','2026-10-19');
select is((select count(*) from public.night_score
 where user_id='20261020-0000-4000-8000-000000000001' and user_day='2026-10-19'),0::bigint,
 'an invalidated night cannot leave its previous score on screen');
select is(pg_temp.score_for_minutes(300),60::numeric,'a valid night can be scored again');
select set_config('request.jwt.claim.sub','20261020-0000-4000-8000-000000000001',true);
select lives_ok($$select public.correct_sleep_window('2026-10-19','23:00','03:00')$$,
 'the existing correction command still works after the score change');
select ok((select score<=40 and (inputs->>'duration_min')::numeric=240
 and (inputs->>'duration_score_cap')::numeric=40 from nb.night_score_parts(
 '20261020-0000-4000-8000-000000000001','2026-10-19')),
 'a corrected four-hour night uses its corrected duration and ceiling');
select ok(not has_function_privilege('authenticated','nb.sleep_duration_score_cap(numeric)','execute'),
 'the internal score policy is not exposed as a client RPC');
select ok(not has_function_privilege('authenticated','nb.night_score_parts(uuid,date)','execute')
 and not has_function_privilege('anon','nb.night_score_parts(uuid,date)','execute'),
 'per-user scoring keeps its existing private privileges');

select * from finish();
rollback;
