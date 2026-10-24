-- target-1.3 composition. Synthetic facts; everything rolls back.
begin;
set search_path=public,extensions;
select no_plan();

-- A good night, then the recommendation is followed with one steady zone-3 run,
-- uploaded and settled every ten minutes as the app does.
insert into auth.users(id) values('13131300-0000-4000-8000-000000000001');
insert into profiles(user_id,timezone,birth_date) values('13131300-0000-4000-8000-000000000001','UTC','1990-01-01');
insert into daily_results(user_id,user_day,algo_version)
 values('13131300-0000-4000-8000-000000000001','2026-09-06',nb.calculation_version());
insert into reserve_daily(result_id,user_id,current_value,drain_drivers)
 select id,user_id,60,'{"close_value":60,"assumed_anchor":false,"anchor_origin":"fixture"}'::jsonb
 from daily_results where user_id='13131300-0000-4000-8000-000000000001';
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line)
 values('13131300-0000-4000-8000-000000000001','2026-09-07',420,60,360,
 '2026-09-07 00:00+00','2026-09-07 07:00+00','0:60,1:360');
insert into raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
 select '13131300-0000-4000-8000-000000000001',t,'UTC',55,50,20,0,1
 from generate_series('2026-09-07 00:00+00'::timestamptz,'2026-09-07 08:55+00',interval '5 minutes') t;
create temporary table steps(label text,clock timestamptz,load numeric,reserve smallint,target jsonb);
create function pg_temp.settle(p_label text,p_clock timestamptz) returns void language plpgsql as $$
begin
 perform set_config('nb.calculation_as_of',p_clock::text,true);
 perform set_config('nb.calculation_day','2026-09-07',true);
 perform nb.settle_day('13131300-0000-4000-8000-000000000001','2026-09-07');
 insert into steps select p_label,p_clock,d.training_load,r.current_value,t.evidence->'target'
 from daily_training t join daily_results d on d.id=t.result_id join reserve_daily r on r.result_id=d.id
 where d.user_id='13131300-0000-4000-8000-000000000001' and d.user_day='2026-09-07';
end $$;
select pg_temp.settle('morning','2026-09-07 09:00+00');
do $$ declare k int; begin
 for k in 0..6 loop
  insert into sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sport_mode,sampled_tz)
  select '13131300-0000-4000-8000-000000000001',gen_random_uuid(),'13131300-0000-4000-8000-0000000000a1',
   '13131300-0000-4000-8000-0000000000b1','2026-09-07 09:00+00'::timestamptz+(k*60+i)*interval '10 seconds',135,1,'UTC'
  from generate_series(0,59+case when k=6 then 1 else 0 end) i;
  insert into raw_samples(user_id,ts,sampled_tz,heart,step,met)
  select '13131300-0000-4000-8000-000000000001',t,'UTC',135,700,7
  from generate_series('2026-09-07 09:00+00'::timestamptz+k*interval '10 minutes',
   '2026-09-07 09:05+00'::timestamptz+k*interval '10 minutes',interval '5 minutes') t;
  perform pg_temp.settle('run',('2026-09-07 09:10+00'::timestamptz+k*interval '10 minutes'));
 end loop;
end $$;
select diag(string_agg(format('%s %s load=%s reserve=%s target=%s base=%s cost=%s',label,to_char(clock,'HH24:MI'),
 load,reserve,target->>'target',target->>'base_target',target->>'movement_cost'),'; ' order by clock)) from steps;

select ok((select bool_and(target->>'version'='target-1.3') from steps),'settlement publishes target-1.3');
select cmp_ok((select reserve from steps order by clock desc limit 1),'<',
 (select reserve from steps where label='morning')-8::smallint,
 'the run itself lowers readiness by more than the 8-point tolerance');
select is((select count(*) from steps where (target->>'target')::numeric<>(target->>'base_target')::numeric),0::bigint,
 'recorded training never lowers its own target');
select is((select count(*) from steps where load<(target->>'base_target')::numeric and (target->>'remaining')::numeric=0),0::bigint,
 'remaining load reaches zero only once the base target has been reached');
select ok((select load>(target->>'target')::numeric from steps order by clock desc limit 1),
 'going past the recommendation is reported against the unchanged target');
select ok((select (target->>'movement_cost')::numeric>8
  and abs((target->>'fatigue_reserve')::numeric-reserve-(target->>'movement_cost')::numeric)<=1
  and (select reserve from steps where label='morning')-(target->>'fatigue_reserve')::numeric<8
 from steps where label='run' order by clock desc limit 1),
 'fatigue is readiness with the movement cost since waking added back');

-- Physiological strain after the same run still lowers the target.
insert into raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
 select '13131300-0000-4000-8000-000000000001',t,'UTC',90,18,90,0,1
 from generate_series('2026-09-07 10:10+00'::timestamptz,'2026-09-07 14:55+00',interval '5 minutes') t;
select pg_temp.settle('strain','2026-09-07 15:00+00');
select cmp_ok((select (target->>'target')::numeric from steps where label='strain'),'<',
 (select (target->>'base_target')::numeric from steps where label='strain'),
 'strain beyond recorded movement still lowers the target');
select ok((select (target->>'reserve_adjustment')::numeric<0 and (target->>'limit_weight')::numeric>0
  and (target->>'target')::numeric>=(target->>'reserve_limit')::numeric from steps where label='strain'),
 'the published adjustment, weight and limit explain the lowered target');

-- The composition is continuous: no single readiness point switches the limit on.
create temporary table sweep as
 select b.base,b.morning,f.fatigue,c.target
 from (values(14.2,66),(14.6,80),(16.0,95),(8.0,90)) b(base,morning)
 cross join generate_series(100,0,-0.5) f(fatigue)
 cross join lateral nb.compose_training_target(b.base,b.morning,f.fatigue) c;
select cmp_ok((select max(abs(target-lag)) from (select target,lag(target) over(partition by base,morning order by fatigue) lag
  from sweep) x where lag is not null),'<=',0.5::numeric,
 'half a readiness point never moves the target by more than half a load point');
select is((select count(*) from sweep where fatigue>=60 and fatigue>=morning-8 and target<>base),0::bigint,
 'ordinary readiness keeps the base target, as in target-1.2');
select is((select count(*) from sweep where (fatigue<=55 or fatigue<=morning-13)
  and target<>least(base,(nb.reserve_training_target(fatigue,fatigue,null)->>'value')::numeric)),0::bigint,
 'beyond the five-point ramp the full reserve limit applies, as in target-1.2');
select ok((select bool_and(target<=base) from sweep),'the reserve limit never raises the base target');
select is((select target from nb.compose_training_target(14.2,null,70)),14.2,
 'an unknown morning applies only the low-readiness rule');
select is((select target from nb.compose_training_target(14.2,66,null)),14.2,
 'without a reserve reading the base target stands');
select is((select target from nb.compose_training_target(null,66,40)),null::numeric,
 'no base target is invented from readiness alone');
select ok(not has_function_privilege('authenticated','nb.compose_training_target(numeric,numeric,numeric)','execute'),
 'the composition helper stays private');

-- The short-night guard has no step: the same night, one minute longer at a time.
insert into auth.users(id) select ('13131300-0000-4000-8000-1'||lpad(m::text,11,'0'))::uuid
 from unnest(array[200,240,300,359,360,361,390,420,449,450,480]) m;
insert into profiles(user_id,timezone,birth_date) select id,'UTC','1990-01-01' from auth.users
 where id::text like '13131300-0000-4000-8000-1%';
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line)
 select ('13131300-0000-4000-8000-1'||lpad(m::text,11,'0'))::uuid,'2026-09-07',m,60,m-60,
  '2026-09-07 00:30+00','2026-09-07 00:30+00'::timestamptz+m*interval '1 minute','0:60,2:90,1:'||(m-150)
 from unnest(array[200,240,300,359,360,361,390,420,449,450,480]) m;
select set_config('nb.calculation_as_of','2026-09-07 15:00+00',true);
select nb.refresh_night_score(user_id,'2026-09-07') from sleep_nights where user_id::text like '13131300-0000-4000-8000-1%';
create temporary table nights as
 select n.total_minutes minutes,(nb.training_recovery_target(n.user_id,'2026-09-07',85::smallint)->>'target')::numeric base
 from sleep_nights n where n.user_id::text like '13131300-0000-4000-8000-1%';
select diag(string_agg(minutes||'min='||base,' ' order by minutes)) from nights;
select cmp_ok((select max(abs(base-lag)) from (select base,lag(base) over(order by minutes) lag,
  minutes-lag(minutes) over(order by minutes) gap from nights) x where gap=1),'<=',0.1::numeric,
 'one more minute of sleep never moves the base target by more than a tenth');
select ok((select bool_and(base>=lag) from (select base,lag(base) over(order by minutes) lag from nights) x
  where lag is not null),'a longer otherwise identical night never lowers the base target');
select ok((select bool_and(base<=8) from nights where minutes<=240),'four hours or less still caps the base at 8');

select * from finish();
rollback;
