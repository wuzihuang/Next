-- The phone's settle request must finish with a realistic baseline and live workout.
begin;
select plan(8);
insert into auth.users(id) values ('21210000-0000-4000-8000-000000000020');
insert into public.profiles(user_id,timezone,birth_date,sex,height_cm)
values ('21210000-0000-4000-8000-000000000020','UTC','1990-01-01','male',180);
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_start,wake_at,sleep_line)
select '21210000-0000-4000-8000-000000000020',d::date,480,100,280,1,d,d+interval '8 hours','0:100,1:280,2:100'
from generate_series('2026-08-18'::timestamptz,'2026-09-15'::timestamptz,interval '1 day') d;
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
select '21210000-0000-4000-8000-000000000020',t,'UTC',
 case when extract(hour from t)<8 then 55 else 75 end,50,25,
 case when extract(hour from t)<8 then 0 else 30 end,case when extract(hour from t)<8 then 1 else 1.3 end
from generate_series('2026-08-18'::timestamptz,'2026-09-15 19:55+00'::timestamptz,interval '5 minutes') t;
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sport_mode,sampled_tz)
select '21210000-0000-4000-8000-000000000020',gen_random_uuid(),
 '21210000-0000-4000-8000-000000000021','21210000-0000-4000-8000-000000000022',t,155,1,'UTC'
from generate_series('2026-09-15 18:00+00'::timestamptz,'2026-09-15 19:00+00'::timestamptz,interval '10 seconds') t;
select set_config('nb.calculation_as_of','2026-09-15 20:00+00',true);
select set_config('nb.calculation_day','2026-09-15',true);

-- Include quiet daytime temperatures, fragmented nights, native HRV, and off-grid
-- sample times; compare the complete baseline JSON to the original implementation.
update public.raw_samples set step=0,temp=32+extract(hour from ts)/24.0
where user_id='21210000-0000-4000-8000-000000000020';
update public.sleep_nights n set sleep_line='0:100,1:120,3:40,2:220',
 raw=jsonb_build_object('hrv',(select jsonb_agg(jsonb_build_object('ts',t,'rmssd_ms',45+extract(minute from t)/10))
  from generate_series(n.sleep_start,n.wake_at-interval '1 minute',interval '1 minute') t))
where user_id='21210000-0000-4000-8000-000000000020';
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv,step,met,temp,src)
select user_id,ts+interval '30 seconds','UTC',95,25,0,1,35,'apple_health'
from public.raw_samples where user_id='21210000-0000-4000-8000-000000000020'
 and extract(hour from ts) in(0,7,8);
insert into auth.users(id) values ('21210000-0000-4000-8000-000000000099');
insert into public.profiles(user_id,timezone) values ('21210000-0000-4000-8000-000000000099','UTC');

-- Keep test-only reference functions private to this transaction/session. Reverse
-- only the two performance transformations, so formula drift remains visible.
do $$ declare def text; original text; begin
 def:=pg_get_functiondef('nb.reserve_baseline(uuid,date)'::regprocedure);
 def:=replace(def,'FUNCTION nb.reserve_baseline(', 'FUNCTION pg_temp.reserve_baseline_before(');
 original:=def;
 def:=replace(def,$old$coalesce((select covered @> s.ts from sleep_lookup),false) sleeping$old$,
  $old$exists(select 1 from sleep m where m.ts>=s.ts and m.ts<s.ts+interval '5 minutes') sleeping$old$);
 if def=original then raise exception 'BASELINE_REFERENCE_ANCHOR_MISSING'; end if;
 execute def;
 def:=pg_get_functiondef('nb.canonical_sleep_nights(uuid,date,date)'::regprocedure);
 def:=replace(def,'FUNCTION nb.canonical_sleep_nights(', 'FUNCTION pg_temp.canonical_sleep_nights_before(');
 original:=def;
 def:=replace(def,$old$), populated as materialized (
  select jsonb_populate_record(null::public.sleep_nights,to_jsonb(c.s)||jsonb_build_object('user_day',c.wake_day)) s from chosen c
 ) select (p.s).* from populated p;$old$,
 $old$) select (jsonb_populate_record(null::public.sleep_nights,to_jsonb(c.s)||jsonb_build_object('user_day',c.wake_day))).* from chosen c;$old$);
 if def=original then raise exception 'CANONICAL_REFERENCE_ANCHOR_MISSING'; end if;
 execute def;
end $$;
select is(nb.reserve_baseline('21210000-0000-4000-8000-000000000020','2026-09-15'),
 pg_temp.reserve_baseline_before('21210000-0000-4000-8000-000000000020','2026-09-15'),
 'complete baseline agrees with the range-scan implementation');
select is(nb.reserve_baseline('21210000-0000-4000-8000-000000000099','2026-09-15'),
 pg_temp.reserve_baseline_before('21210000-0000-4000-8000-000000000099','2026-09-15'),
 'empty account baseline is unchanged');
select is((nb.reserve_baseline('21210000-0000-4000-8000-000000000099','2026-09-15')->>'rhr_nights')::int,0,
 'a second account cannot consume the populated account sleep evidence');
select results_eq(
 $$select to_jsonb(n) from nb.canonical_sleep_nights('21210000-0000-4000-8000-000000000020','2026-09-01','2026-09-15') n order by user_day$$,
 $$select to_jsonb(n) from pg_temp.canonical_sleep_nights_before('21210000-0000-4000-8000-000000000020','2026-09-01','2026-09-15') n order by user_day$$,
 'canonical rows including raw native HRV are unchanged');
select ok((select bool_and(old_match=new_match) from (
 select exists(select 1 from (values ('2026-09-01 03:00Z'::timestamptz),('2026-09-01 03:01Z'::timestamptz),('2026-09-01 03:20Z'::timestamptz)) m(ts)
  where m.ts>=s.ts and m.ts<s.ts+interval '5 minutes') old_match,
 (select range_agg(tstzrange(m.ts-interval '5 minutes',m.ts,'(]')) @> s.ts from
 (values ('2026-09-01 03:00Z'::timestamptz),('2026-09-01 03:01Z'::timestamptz),('2026-09-01 03:20Z'::timestamptz)) m(ts)) new_match
 from generate_series('2026-09-01 02:54:59Z'::timestamptz,'2026-09-01 03:20:01Z'::timestamptz,interval '1 second') s(ts)
 ) comparisons), 'range membership preserves gaps, both endpoints and off-grid seconds');
do $$ declare started timestamptz:=clock_timestamp(); elapsed numeric; begin
 perform nb.settle_day('21210000-0000-4000-8000-000000000020','2026-09-15');
 elapsed:=extract(epoch from(clock_timestamp()-started));
 perform set_config('nb.test_reserve_settle_seconds',elapsed::text,true);
 raise notice 'Native HRV + fragmented sleep + off-grid samples + workout settlement: % seconds',elapsed;
end $$;
select cmp_ok(current_setting('nb.test_reserve_settle_seconds')::numeric,'<',8::numeric,
 'native HRV settlement fits the phone request budget');
select ok((select r.current_value is not null from public.reserve_daily r join public.daily_results d on d.id=r.result_id
 where d.user_id='21210000-0000-4000-8000-000000000020' and d.user_day='2026-09-15'),
 'settlement publishes Body Battery');
select ok(not has_function_privilege('authenticated','nb.reserve_baseline(uuid,date)','EXECUTE')
 and not has_function_privilege('authenticated','nb.canonical_sleep_nights(uuid,date,date)','EXECUTE'),
 'internal functions retain their access boundary');
select * from finish();
rollback;
