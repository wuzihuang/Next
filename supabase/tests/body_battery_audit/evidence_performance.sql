-- Large native JSON with many five-minute fallback minutes reproduces the
-- production cost. Compare every evidence output before and after the migration,
-- including an invalidation in a fallback slot rather than a native slot.
begin;
do $$ declare uid uuid:='00000000-0000-0000-0000-000000000019'; begin
 if to_regclass('auth.users') is not null then
  insert into auth.users(id) values(uid) on conflict do nothing;
 end if;
 insert into public.profiles(user_id,timezone) values(uid,'UTC') on conflict do nothing;
end $$;
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line,raw)
select '00000000-0000-0000-0000-000000000019',d::date,658,658,0,
 d-interval '2 hours',d+interval '8 hours 58 minutes','0:658',
 jsonb_build_object('hrv',(
  select jsonb_agg(jsonb_build_object('ts',to_char(d-interval '2 hours'+i*interval '1 minute','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
   'rmssd_ms',60+i%7,'observed_at','2026-09-05T12:00:00Z') order by i)
  from generate_series(0,341) i))
 ||case when d::date='2026-09-05' then jsonb_build_object('hrv_invalidated',jsonb_build_array(
   jsonb_build_object('ts','2026-09-05T04:40:00Z','observed_at','2026-09-05T13:00:00Z')))
 else '{}'::jsonb end
from generate_series('2026-09-04'::timestamptz,'2026-09-05'::timestamptz,interval '1 day') d;
insert into public.raw_samples(user_id,ts,src,heart,hrv,step,met)
select '00000000-0000-0000-0000-000000000019',d-interval '2 hours'+i*interval '1 minute','band',55,50,0,1
from generate_series('2026-09-04'::timestamptz,'2026-09-05'::timestamptz,interval '1 day') d
cross join generate_series(0,655,5) i;
create temporary table evidence_before as
select d::date as day,to_jsonb(e) as evidence
from generate_series('2026-09-04'::date,'2026-09-05'::date,interval '1 day') d
cross join lateral nb.night_evidence_parts_at('00000000-0000-0000-0000-000000000019',d::date,'2026-09-06T00:00:00Z') e;
\ir /tmp/body_battery_evidence_performance.sql
do $$ declare r record; output jsonb; begin
 for r in select * from evidence_before loop
  select to_jsonb(e) into output from nb.night_evidence_parts_at('00000000-0000-0000-0000-000000000019',r.day,'2026-09-06T00:00:00Z') e;
  if output is distinct from r.evidence then raise exception 'materialized invalidation changed evidence for %',r.day; end if;
  if (output->>'expected_minutes')::integer<>658 or (output->>'rhr_minutes')::integer<>658
    or output->>'hrv_source'<>'mixed_rmssd' then raise exception 'large-night fixture did not exercise mixed native/fallback coverage'; end if;
  if (output->>'hrv_minutes')::integer<>(case when r.day='2026-09-05' then 654 else 655 end)
    then raise exception 'fallback invalidation did not remove exactly one covered minute'; end if;
 end loop;
 raise notice 'large-night evidence equivalence and fallback invalidation assertions passed';
end $$;
rollback;
