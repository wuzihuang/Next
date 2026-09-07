begin;
select plan(6);
insert into auth.users(id) values('0b0b0b0b-0000-0000-0000-000000000030');
insert into public.profiles(user_id,timezone,birth_date) values('0b0b0b0b-0000-0000-0000-000000000030','UTC','1990-01-01');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,met)
select '0b0b0b0b-0000-0000-0000-000000000030',(nb.user_day_of(now(),'UTC')-5)::timestamp+interval '8 hours'+(g||' days')::interval,'UTC',80,1
from generate_series(0,5) g;
select set_config('nb.today',nb.user_day_of(now(),'UTC')::text,true);
insert into nb.calculation_work(user_id,dirty_from) values('0b0b0b0b-0000-0000-0000-000000000030',current_setting('nb.today')::date-5)
 on conflict(user_id) do update set dirty_from=excluded.dirty_from;
-- An already-expired deadline still settles one day and records where to resume.
select set_config('nb.calculation_deadline',(clock_timestamp()-interval '1 second')::text,true);
select is(nb.recompute_range('0b0b0b0b-0000-0000-0000-000000000030',current_setting('nb.today')::date,current_setting('nb.today')::date,'test'),1,'an expired deadline still settles at least one day');
select is((select dirty_from from nb.calculation_work where user_id='0b0b0b0b-0000-0000-0000-000000000030'),current_setting('nb.today')::date-4,'the first unsettled day is recorded as dirty');
select is((select count(*)::int from public.daily_results where user_id='0b0b0b0b-0000-0000-0000-000000000030'),1,'only the settled day is published');
select is(nb.recompute_range('0b0b0b0b-0000-0000-0000-000000000030',current_setting('nb.today')::date,current_setting('nb.today')::date,'test'),1,'the next call resumes from the recorded day');
select is((select dirty_from from nb.calculation_work where user_id='0b0b0b0b-0000-0000-0000-000000000030'),current_setting('nb.today')::date-3,'and advances the resume point by one day');
-- Without a deadline the whole chain settles in one call, as before.
select set_config('nb.calculation_deadline','',true);
select ok(nb.recompute_range('0b0b0b0b-0000-0000-0000-000000000030',current_setting('nb.today')::date,current_setting('nb.today')::date,'test')>=4
  and (select dirty_from is null from nb.calculation_work where user_id='0b0b0b0b-0000-0000-0000-000000000030'),'no deadline settles the rest and clears dirty_from');
select * from finish();
rollback;
