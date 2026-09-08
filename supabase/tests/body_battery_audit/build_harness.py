#!/usr/bin/env python3
"""Extract production formula bodies; the README records the integration scope."""
from pathlib import Path
import re
import sys
root=Path(__file__).resolve().parents[2] / 'migrations'
def f(file,name):
 t=(root/file).read_text()
 m=re.search(r'create or replace function nb\.'+re.escape(name)+r'\([\s\S]+?\$\$;',t,re.I)
 assert m,name
 return m[0]+'\n'
schema='''create schema nb;
create role anon; create role authenticated;
create table public.profiles(user_id uuid primary key, timezone text,birth_date date);
create table public.raw_samples(user_id uuid,ts timestamptz,heart smallint,hrv numeric,stress smallint,step integer,met numeric,sleep_states smallint,src text default 'band',primary key(user_id,ts,src));
create table public.sleep_nights(user_id uuid,user_day date,total_minutes integer,deep_minutes integer,light_minutes integer,sleep_start timestamptz,wake_at timestamptz,sleep_line text,raw jsonb,primary key(user_id,user_day));
create table public.daily_results(id uuid primary key default gen_random_uuid(),user_id uuid,user_day date,algo_version text,unique(user_id,user_day));
create table public.reserve_daily(result_id uuid primary key,user_id uuid,wake_value smallint,current_value smallint,min_value smallint,drain_drivers jsonb);
create table public.reserve_samples(user_id uuid,ts timestamptz,value smallint,source text);
'''
for name in ['user_day_bounds','user_day_of','hr_max']: schema+=f('20260901120200_compute.sql',name)
schema+=f('20260902070000_settle_now.sql','hr_rest')
schema+=f('20260905090300_indexed_night_baselines.sql','night_rhr')
for name in ['night_hrv_parts','night_hrv','charge_multiplier','night_inputs']: schema+=f('20260903120000_night_hrv_sleep_window.sql',name)
schema+=f('20260903150000_recompute_body_battery_v2.sql','reserve_anchor')
for name in ['reserve_replay','compute_reserve']: schema+=f('20260903140000_body_battery_realtime.sql',name)
schema+='''
create function nb.calculation_profile(p_user uuid,p_day date) returns setof public.profiles language sql stable as $$ select * from public.profiles where user_id=p_user $$;
create function nb.calculation_clock() returns timestamptz language sql stable as $$ select coalesce(nullif(current_setting('nb.calculation_as_of',true),'')::timestamptz,'2026-09-06 16:00Z'::timestamptz) $$;
create function nb.calculation_instant(p_user uuid,p_day date) returns timestamptz language sql stable as $$ select least(coalesce(nullif(current_setting('nb.calculation_as_of',true),'')::timestamptz,'2026-09-06 16:00Z'::timestamptz),b.ends_at) from public.profiles p cross join lateral nb.user_day_bounds(p_day,p.timezone) b where p.user_id=p_user $$;
alter function nb.reserve_replay(uuid,date) rename to reserve_replay_uncached;
'''
# Load the actual transaction cache wrapper, not a stand-in replay.
t=(root/'20260904085910_reproducible_calculation_revisions.sql').read_text()
schema+=re.search(r'create function nb.reserve_replay\([\s\S]+?\$\$;',t)[0]+'\n'
# Integration-only version/publication machinery is separately tested against all migrations.
schema+=(root/'20260906130331_body_battery_evidence_contract.sql').read_text().split('-- Keep publication, caching, historical profile/clock, archive recovery and locking.')[0]
# The calibrated replay replaces the bb-2.1 body wholesale, so it is loaded last.
# The harness keeps the bb-2.1 version strings: it audits the formula, not publication.
schema+=f('20260908090000_everyday_load_and_reserve_calibration.sql','reserve_replay_uncached')
schema+='''
create function nb.audit_save(p_user uuid,p_day date) returns void language plpgsql as $$
declare id uuid;
begin
 insert into daily_results(user_id,user_day,algo_version) values(p_user,p_day,'bb-2.1/calc-1') returning daily_results.id into id;
 insert into reserve_daily(result_id,user_id,wake_value,current_value,min_value,drain_drivers) select id,p_user,r.wake_value,r.current_value,r.min_value,r.drivers from nb.compute_reserve(p_user,p_day) r;
 insert into reserve_samples select p_user,r.ts,round(r.value),'model' from nb.reserve_replay(p_user,p_day) r;
end $$;
'''
Path(sys.argv[1]).write_text(schema)
