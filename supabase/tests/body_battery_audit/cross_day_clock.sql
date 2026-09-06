-- Preserve the same as-of limit when a later result reads an earlier night's ledger.
insert into profiles(user_id,timezone,birth_date) values ('10000000-0000-0000-0000-000000000005','UTC',null);
insert into daily_results(id,user_id,user_day,algo_version) values ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000005','2026-09-02','bb-2.1/calc-1');
insert into reserve_daily(result_id,user_id,current_value,drain_drivers) values ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000005',20,'{"close_value":20,"assumed_anchor":true}');
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line) select '10000000-0000-0000-0000-000000000005',d::date,480,480,0,d::date-1+'22:00'::time,d::date+'06:00'::time,'0:480' from generate_series('2026-08-21'::date,'2026-09-04'::date,interval '1 day')d;
insert into raw_samples(user_id,ts,heart,hrv) select '10000000-0000-0000-0000-000000000005',t,case when t>='2026-09-03 22:00Z' then 30 else 60 end,60 from generate_series('2026-08-20 22:00Z'::timestamptz,'2026-09-04 05:55Z'::timestamptz,interval '5 minutes')t;
do $$ declare before numeric; after numeric; charge numeric; expected numeric; actual numeric;
begin
 perform set_config('nb.calculation_as_of','2026-09-04 04:00Z',true);
 perform nb.audit_save('10000000-0000-0000-0000-000000000005','2026-09-03');
 select r.value into before from nb.reserve_replay('10000000-0000-0000-0000-000000000005','2026-09-03')r order by ts desc limit 1;
 with r as materialized(select * from nb.reserve_replay('10000000-0000-0000-0000-000000000005','2026-09-03')) select (select d_charge from r order by ts desc limit 1)-(select d_charge from r where ts<'2026-09-03 22:00Z' order by ts desc limit 1) into charge;
 perform set_config('nb.calculation_as_of','2026-09-04 16:00Z',true);
 select r.value into after from nb.reserve_replay('10000000-0000-0000-0000-000000000005','2026-09-03')r order by ts desc limit 1;
 perform audit_check('child_day_uses_its_own_clock',before=after,jsonb_build_object('before',round(before,4),'after',round(after,4)),'Later ambient time cannot change a completed child-day ledger.');
 select charge+r.d_charge into expected from nb.reserve_replay('10000000-0000-0000-0000-000000000005','2026-09-04')r order by ts desc limit 1;
 select (r.drivers->>'night_charge')::numeric into actual from nb.compute_reserve('10000000-0000-0000-0000-000000000005','2026-09-04')r;
 perform audit_check('night_charge_uses_published_day_ledgers',actual=round(expected),jsonb_build_object('actual',actual,'expected',round(expected,4)),'Night charge sums the same two ledgers used by the carried reserve.');
 perform set_config('nb.calculation_as_of','',true);
end $$;
-- Measure one dense 14-night baseline plus current reserve, with the real functions.
\timing on
select current_value,drivers->>'night_charge' night_charge from nb.compute_reserve('10000000-0000-0000-0000-000000000005','2026-09-04');
\timing off
