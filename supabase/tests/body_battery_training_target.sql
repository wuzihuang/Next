begin;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id) values('30303000-0000-4000-8000-000000000001');
insert into profiles(user_id,timezone,birth_date) values('30303000-0000-4000-8000-000000000001','UTC','1990-01-01');
insert into daily_results(user_id,user_day,algo_version)
 values('30303000-0000-4000-8000-000000000001','2026-09-06',nb.calculation_version());
insert into reserve_daily(result_id,user_id,current_value,drain_drivers)
 select id,user_id,60,'{"close_value":60,"assumed_anchor":false,"anchor_origin":"fixture"}'::jsonb
 from daily_results where user_id='30303000-0000-4000-8000-000000000001';
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line)
 values('30303000-0000-4000-8000-000000000001','2026-09-07',420,60,360,
 '2026-09-07 00:00+00','2026-09-07 07:00+00','0:60,1:360');
insert into raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
 select '30303000-0000-4000-8000-000000000001',t,'UTC',55,50,20,0,1
 from generate_series('2026-09-07 00:00+00'::timestamptz,'2026-09-07 07:55+00',interval '5 minutes') t;
select set_config('nb.calculation_as_of','2026-09-07 08:00+00',true);
select set_config('nb.calculation_day','2026-09-07',true);
select nb.settle_day('30303000-0000-4000-8000-000000000001','2026-09-07');
create temporary table targets(label text,target jsonb,load numeric,wake smallint);
insert into targets select 'morning',t.evidence->'target',d.training_load,r.wake_value from daily_training t
 join daily_results d on d.id=t.result_id join reserve_daily r on r.result_id=d.id
 where d.user_id='30303000-0000-4000-8000-000000000001' and d.user_day='2026-09-07';
insert into raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
 select '30303000-0000-4000-8000-000000000001',t,'UTC',90,18,90,0,1
 from generate_series('2026-09-07 08:00+00'::timestamptz,'2026-09-07 13:55+00',interval '5 minutes') t;
select set_config('nb.calculation_as_of','2026-09-07 14:00+00',true);
select nb.settle_day('30303000-0000-4000-8000-000000000001','2026-09-07');
insert into targets select 'strained',t.evidence->'target',d.training_load,r.wake_value from daily_training t
 join daily_results d on d.id=t.result_id join reserve_daily r on r.result_id=d.id
 where d.user_id='30303000-0000-4000-8000-000000000001' and d.user_day='2026-09-07';
insert into raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
 select '30303000-0000-4000-8000-000000000001',t,'UTC',55,50,20,0,1
 from generate_series('2026-09-07 14:00+00'::timestamptz,'2026-09-07 17:55+00',interval '5 minutes') t;
select set_config('nb.calculation_as_of','2026-09-07 18:00+00',true);
select nb.settle_day('30303000-0000-4000-8000-000000000001','2026-09-07');
insert into targets select 'rested',t.evidence->'target',d.training_load,r.wake_value from daily_training t
 join daily_results d on d.id=t.result_id join reserve_daily r on r.result_id=d.id
 where d.user_id='30303000-0000-4000-8000-000000000001' and d.user_day='2026-09-07';
select diag(string_agg(label||': target='||(target->>'target')||', base='||(target->>'base_target')||', reserve='||(target->>'current_reserve'),'; ')) from targets;
select ok((select bool_and(target->>'version'='target-1.1') from targets),'settlement publishes the composed target model');
select is((select count(distinct wake) from targets),1::bigint,'the actual morning reserve is not rewritten during the day');
select is((select count(distinct target->>'base_target') from targets),1::bigint,'the sleep/recovery base survives all daytime adjustments');
select cmp_ok((select (target->>'target')::numeric from targets where label='strained'),'<',
 (select (target->>'target')::numeric from targets where label='morning'),'ongoing strain lowers the published target');
select cmp_ok((select (target->>'target')::numeric from targets where label='rested'),'>',
 (select (target->>'target')::numeric from targets where label='strained'),'daytime rest restores part of the target');
select ok((select bool_and((target->>'target')::numeric<=(target->>'base_target')::numeric) from targets),'recovery never raises the recommendation beyond the sleep/recovery base');
select cmp_ok((select load from targets where label='rested'),'>=',(select load from targets where label='strained'),'completed training is not erased when the recommendation changes');
select ok((select bool_and((target->>'remaining')::numeric=greatest(0,(target->>'target')::numeric-load)) from targets),'remaining guidance never becomes negative');
select set_config('nb.calculation_as_of','2026-09-07 20:00+00',true);
select is(nb.training_target('30303000-0000-4000-8000-000000000001','2026-09-07',(select wake from targets limit 1))->>'target',(select target->>'target' from targets where label='rested'),
 'missing fresh battery evidence cannot restore an old high target');
select is(nb.reserve_training_target(40,60,15)->>'value','8.0','a lower current reserve reduces guidance immediately');
select is(nb.reserve_training_target(60,40,15)->>'value','8.0','a sudden recovery waits for the recent-window average');
select ok(not has_function_privilege('authenticated','nb.training_recovery_target(uuid,date,smallint)','execute'),'the base helper keeps existing authorization boundaries');
select is((nb.training_target('30303000-0000-4000-8000-000000000001','2026-09-07',(select wake from targets limit 1))->>'reserve_fresh')::boolean,false,
 'retained guidance marks the original battery observation stale');
select * from finish();
rollback;
