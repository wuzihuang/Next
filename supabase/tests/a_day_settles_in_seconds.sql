-- 20260912150000 · a night's evidence is computed once per settle, a day's replay once per
-- transaction, and settle_now stops before the caller's statement budget.
begin;
select plan(17);
insert into auth.users(id) values('0c0c0c0c-0000-0000-0000-000000000031');
insert into public.profiles(user_id,timezone,birth_date) values('0c0c0c0c-0000-0000-0000-000000000031','UTC','1990-01-01');
select set_config('nb.today',nb.user_day_of(now(),'UTC')::text,true);
-- Sixteen nights with native HRV and a wrist that was there: every baseline night is usable.
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line,raw)
select '0c0c0c0c-0000-0000-0000-000000000031',d,420,120,300,
 d::timestamp+interval '23 hours'-interval '1 day',d::timestamp+interval '6 hours','0:120,1:300',
 jsonb_build_object('hrv',(select jsonb_agg(jsonb_build_object('ts',to_char(d::timestamp+interval '23 hours'-interval '1 day'+i*interval '1 minute','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'rmssd_ms',40+i%9)) from generate_series(0,419) i))
from generate_series(current_setting('nb.today')::date-16,current_setting('nb.today')::date-1,interval '1 day') d;
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
select '0c0c0c0c-0000-0000-0000-000000000031',t,'UTC',case when extract(hour from t) between 0 and 5 then 52 else 70 end,45,30,
 case when extract(hour from t) between 8 and 20 then 40 else 0 end,case when extract(hour from t) between 8 and 20 then 1.6 else 1 end
from generate_series((current_setting('nb.today')::date-17)::timestamptz,(current_setting('nb.today')::date-1)::timestamptz+interval '23 hours 55 minutes',interval '5 minutes') t;

-- Count the engine behind the memo at its own seam, as calculation_revisions.sql does.
create temporary sequence evidence_calls;
create temporary sequence replay_calls;
create temporary sequence ticks_calls;
do $$ declare f text; begin
 f:=pg_get_functiondef('nb.night_evidence_parts_at_uncached(uuid,date,timestamptz)'::regprocedure);
 f:=replace(f,'AS $function$'||chr(10),'AS $function$'||chr(10)||' select nextval(''pg_temp.evidence_calls'');'||chr(10));
 execute f;
 f:=pg_get_functiondef('nb.reserve_replay_uncached(uuid,date)'::regprocedure);
 f:=replace(f,'begin'||chr(10),'begin'||chr(10)||'perform nextval(''pg_temp.replay_calls'');'||chr(10));
 execute f;
 f:=pg_get_functiondef('nb.training_load_ticks_uncached(uuid,date)'::regprocedure);
 f:=replace(f,'AS $function$'||chr(10),'AS $function$'||chr(10)||' select nextval(''pg_temp.ticks_calls'');'||chr(10));
 execute f;
end $$;

-- 0 · the wrappers are as private as their engines.
select ok(not has_function_privilege('authenticated','nb.night_evidence_parts_at(uuid,date,timestamptz)','EXECUTE')
  and not has_function_privilege('anon','nb.night_evidence_parts_at(uuid,date,timestamptz)','EXECUTE')
  and not has_function_privilege('authenticated','nb.training_load_ticks(uuid,date)','EXECUTE'),
 'the memo wrappers are not client APIs');

-- 1 · the memo answers what the engine answers.
select is(
 (select to_jsonb(e) from nb.night_evidence_parts_at('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date-3,now()) e),
 (select to_jsonb(e) from nb.night_evidence_parts_at_uncached('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date-3,now()) e),
 'the memoised night evidence equals the engine''s');
select is((select last_value::int from evidence_calls),2,'one engine call from each side of the comparison');
select is(
 (select to_jsonb(e) from nb.night_evidence_parts_at('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date-3,now()) e),
 (select to_jsonb(e) from nb.night_evidence_parts_at_uncached('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date-3,now()) e),
 'asked again, the memo still equals the engine');
select is((select last_value::int from evidence_calls),3,'and only the engine side ran again');
-- A night that has woken answers the same under any later as-of, from the memo.
select is(
 (select to_jsonb(e) from nb.night_evidence_parts_at('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date-3,now()+interval '3 hours') e),
 (select to_jsonb(e) from nb.night_evidence_parts_at_uncached('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date-3,now()+interval '3 hours') e),
 'a closed night reads the same under a later as-of');
select is((select last_value::int from evidence_calls),4,'and the memo answered it without the engine');
-- A night still in progress keeps its exact as-of: asked as of its middle, the engine runs.
select is((select count(*)::int from nb.night_evidence_parts_at('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date-3,(current_setting('nb.today')::date-3)::timestamptz+interval '3 hours') e),1,'an as-of inside the night still answers');
select is((select last_value::int from evidence_calls),5,'from the engine, not from the closed memo');

-- 2 · a late fact re-dirties yesterday: every night at most once per day settled, and a
-- day's replay exactly once — yesterday, the day its night began on, and today.
insert into nb.calculation_work(user_id,dirty_from) values('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date-16)
 on conflict(user_id) do update set dirty_from=excluded.dirty_from;
select nb.recompute_range('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date,current_setting('nb.today')::date,'test');
select nb.invalidate_calculation('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date-1);
-- Outside a settle the training ticks go to the engine every time: sport samples carry no
-- invalidation trigger, so two calls in one transaction may see different facts.
select setval('ticks_calls',1,false);
select is(
 (select count(*) from nb.training_load_ticks('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date-1)),
 (select count(*) from nb.training_load_ticks_uncached('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date-1)),
 'outside a settle the ticks wrapper answers what the engine answers');
select is((select last_value::int from ticks_calls),2,'and goes to the engine for each call');
select setval('evidence_calls',1,false);
select setval('replay_calls',1,false);
select setval('ticks_calls',1,false);
select set_config('nb.settled',nb.recompute_range('0c0c0c0c-0000-0000-0000-000000000031',current_setting('nb.today')::date,current_setting('nb.today')::date,'test')::text,true);
select is(current_setting('nb.settled')::int,2,'yesterday and today settle again');
select is((select last_value::int from ticks_calls),2,'inside a settle the training ticks are built once per day');
-- Sixteen nights under the as-of instants a two-day settle asks under stays far below the
-- 230 engine calls a single day cost before this migration.
select ok((select last_value::int from evidence_calls) between 1 and 70,
 format('night evidence engine ran %s times for two days, not hundreds',(select last_value from evidence_calls)));
select is((select last_value::int from replay_calls),3,'yesterday, the day its night began on, and today: each replayed once');
select ok((select r.reserve_score is not null and r.worn from public.daily_results r
  where r.user_id='0c0c0c0c-0000-0000-0000-000000000031' and r.user_day=current_setting('nb.today')::date-1),
 'the closed day has a body battery and was worn');

-- 3 · settle_now under a statement budget settles at least one day and records the rest.
do $$ declare f text; begin
 f:=pg_get_functiondef('nb.settle_day(uuid,date)'::regprocedure);
 f:=replace(f,'begin'||chr(10),'begin'||chr(10)||'  perform pg_sleep(1.5);'||chr(10));
 execute f;
end $$;
update nb.calculation_work set dirty_from=current_setting('nb.today')::date-8 where user_id='0c0c0c0c-0000-0000-0000-000000000031';
select set_config('request.jwt.claim.sub','0c0c0c0c-0000-0000-0000-000000000031',true);
-- Half of six seconds: the first day ends past 1.5 s, the second starts under 3 s and ends
-- past it, the third never starts. Nine days were dirty; the rest is recorded.
set local statement_timeout='6s';
set local role authenticated;
select set_config('nb.app_settled',public.settle_now(0)::text,true);
reset role;
set local statement_timeout=0;
select ok(current_setting('nb.app_settled')::int between 1 and 3
  and (select dirty_from from nb.calculation_work where user_id='0c0c0c0c-0000-0000-0000-000000000031')
      =current_setting('nb.today')::date-8+current_setting('nb.app_settled')::int,
 format('settle_now stopped at half of a 6 s budget after %s days and recorded the resume point',current_setting('nb.app_settled')));
select * from finish();
rollback;
