#!/usr/bin/env python3
"""Synthetic, rollback-only SQL strategy benchmark; never accepts a remote database URL."""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
CONTAINER = "nextbody-calculation-test"
USER = "09090909-0000-0000-0000-000000000099"

def old_function(filename, name):
    source = (ROOT / "supabase/migrations" / filename).read_text()
    matches = re.findall(r"create or replace function " + re.escape(name) + r"\(.*?\n\$\$;", source, re.S)
    if not matches:
        raise RuntimeError(f"Missing baseline definition: {name}")
    return matches[-1]

legacy_settle = old_function("20260901120200_compute.sql", "nb.settle_day")
legacy_settle = legacy_settle.replace("bb-1.4", "bb-2.0").replace("v_reserve.wake_value is not null", "v_reserve.current_value is not null")
legacy_curve = old_function("20260901130000_reserve_replay.sql", "nb.materialize_reserve_curve")
legacy_recompute = old_function("20260903120000_night_hrv_sleep_window.sql", "nb.recompute_range")
setup = f"""
begin;
set local statement_timeout='240s';
create temporary table benchmark_times(strategy text, elapsed_ms numeric, replay_count int, rows_touched int);
create temporary table benchmark_reads(kind text, elapsed_ms numeric, json_bytes int, source_rows int);
insert into auth.users(id) values('{USER}');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date) values('{USER}','UTC','male',180,'1990-01-01');
select set_config('nb.benchmark_day',nb.user_day_of(now(),'UTC')::text,true);
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id)
values('{USER}',(current_setting('nb.benchmark_day')::date-183)+interval '5 hours',75,'manual','09090909-0000-0000-0000-000000000098');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,met,stress)
select '{USER}',d+interval '8 hours'+i*interval '5 minutes','UTC',(70+i%10)::smallint,1.2,(20+i%5)::smallint
from generate_series(current_setting('nb.benchmark_day')::date-182,current_setting('nb.benchmark_day')::date-1,interval '1 day') d
cross join generate_series(0,11) i;
select nb.recompute_range('{USER}',current_setting('nb.benchmark_day')::date-182,current_setting('nb.benchmark_day')::date,'benchmark_setup');
create temporary sequence benchmark_replays;
grant all on sequence benchmark_replays to postgres;
do $$ declare f text;begin
 f:=pg_get_functiondef('nb.reserve_replay_uncached(uuid,date)'::regprocedure);
 f:=replace(f,'begin'||chr(10),'begin'||chr(10)||'perform nextval(''pg_temp.benchmark_replays'');'||chr(10));
 execute f;
end $$;
select set_config('nb.calculation_day',(current_setting('nb.benchmark_day')::date-1)::text,true);
select set_config('nb.calculation_as_of',(current_setting('nb.benchmark_day')::date+interval '4 hours')::text,true);
"""

def calculation_measure(strategy, writer=False):
    statement = (f"perform nb.settle_day('{USER}',current_setting('nb.benchmark_day')::date-1); n:=1;" if writer else
                 f"n:=nb.recompute_range('{USER}',current_setting('nb.benchmark_day')::date-1,current_setting('nb.benchmark_day')::date-1,'benchmark_{strategy}');")
    return f"""
do $$ declare i int; start_at timestamptz; n int; before_calls int; after_calls int;begin
 for i in 1..35 loop
 select case when is_called then last_value::int else 0 end into before_calls from benchmark_replays;
 start_at:=clock_timestamp();
 {statement}
 select case when is_called then last_value::int else 0 end into after_calls from benchmark_replays;
 if i>3 then insert into benchmark_times values('{strategy}',extract(epoch from clock_timestamp()-start_at)*1000,after_calls-before_calls,n);end if;
 end loop;
end $$;
"""

read_measure = f"""
do $$ declare i int; started timestamptz; payload jsonb; points int;begin
 select count(*) into points from public.reserve_samples where user_id='{USER}'
 and ts>=current_setting('nb.benchmark_day')::date-182+interval '4 hours' and ts<current_setting('nb.benchmark_day')::date+interval '4 hours';
 for i in 1..35 loop
 started:=clock_timestamp();
 select jsonb_agg(to_jsonb(d) order by d.user_day) into payload from public.daily_results d
 where d.user_id='{USER}' and d.user_day>=current_setting('nb.benchmark_day')::date-182 and d.user_day<current_setting('nb.benchmark_day')::date;
 if i>3 then insert into benchmark_reads values('summary_182_days',extract(epoch from clock_timestamp()-started)*1000,octet_length(payload::text),182);end if;
 started:=clock_timestamp();
 select jsonb_agg(jsonb_build_object('daily',to_jsonb(d),'training',to_jsonb(t),'reserve',to_jsonb(r),'fuel',to_jsonb(f),
 'reserve_samples',(select coalesce(jsonb_agg(to_jsonb(s) order by s.ts),'[]') from public.reserve_samples s where s.user_id=d.user_id and s.ts>=d.user_day+interval '4 hours' and s.ts<d.user_day+interval '28 hours')) order by d.user_day)
 into payload from public.daily_results d
 left join public.daily_training t on t.result_id=d.id
 left join public.reserve_daily r on r.result_id=d.id
 left join public.day_fuel f on f.result_id=d.id
 where d.user_id='{USER}' and d.user_day>=current_setting('nb.benchmark_day')::date-182 and d.user_day<current_setting('nb.benchmark_day')::date;
 if i>3 then insert into benchmark_reads values('summary_and_detail_182_days',extract(epoch from clock_timestamp()-started)*1000,octet_length(payload::text),182*4+points);end if;
 end loop;
end $$;
"""
legacy_wrapper = """
create or replace function nb.reserve_replay(p_user uuid,p_user_day date)
returns table(ts timestamptz,value numeric,asleep boolean,d_charge numeric,d_basal numeric,d_active numeric,d_stress numeric)
language sql stable set search_path='' as $$ select * from nb.reserve_replay_uncached(p_user,p_user_day); $$;
"""
result_sql = """
select jsonb_build_object('type','calculation','strategy',strategy,'runs',count(*),
 'p50_ms',round(percentile_cont(.5) within group(order by elapsed_ms)::numeric,3),
 'p95_ms',round(percentile_cont(.95) within group(order by elapsed_ms)::numeric,3),
 'replays_per_request',round(avg(replay_count),2),'rows_touched_per_request',round(avg(rows_touched),2))
from benchmark_times group by strategy;
select jsonb_build_object('type','reads','strategy',kind,'runs',count(*),
 'p50_ms',round(percentile_cont(.5) within group(order by elapsed_ms)::numeric,3),
 'p95_ms',round(percentile_cont(.95) within group(order by elapsed_ms)::numeric,3),
 'json_bytes',max(json_bytes),'source_rows',max(source_rows)) from benchmark_reads group by kind;
rollback;
"""
sql = setup + calculation_measure("revision_skip") + calculation_measure("current_writer_forced_recompute", writer=True) + read_measure + legacy_settle + legacy_curve + legacy_recompute + legacy_wrapper + calculation_measure("legacy_recompute_strategy") + result_sql
result = subprocess.run(["docker", "exec", "-i", CONTAINER, "psql", "-X", "-q", "-A", "-t", "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1"], input=sql, text=True, capture_output=True)
if result.returncode:
    sys.stderr.write(result.stderr)
    raise SystemExit(result.returncode)
for line in result.stdout.splitlines():
    if line.startswith('{'):
        print(json.dumps(json.loads(line), sort_keys=True))
