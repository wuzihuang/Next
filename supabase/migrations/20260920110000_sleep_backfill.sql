-- A reported window is a fact supplied by the wearer. Physiology is recovered from
-- observations inside that window; missing stages remain unknown. Original band
-- intervals/offsets survive corrections and clearing restores the band's own receipt.

create or replace function nb.resolve_reported_sleep_window(p_user uuid,p_day date,p_start text,p_end text)
returns table(starts_at timestamptz,ends_at timestamptz)
language plpgsql stable set search_path='' as $$
declare zone text; local_start timestamp; local_end timestamp; start_time time; end_time time;
begin
 select coalesce(timezone,'UTC') into zone from public.profiles where user_id=p_user;
 zone:=coalesce(zone,'UTC');
 if p_day is null or p_day>nb.user_day_of(nb.calculation_clock(),zone)
 then raise exception 'NO_SLEEP_NIGHT' using errcode='22023'; end if;
 if p_day<nb.user_day_of(nb.calculation_clock(),zone)-30
 then raise exception 'CORRECTION_TOO_OLD' using errcode='22023'; end if;
 if coalesce(trim(p_start),'')!~ '^\d{1,2}:\d{2}(:\d{2})?$'
 or coalesce(trim(p_end),'')!~ '^\d{1,2}:\d{2}(:\d{2})?$'
 then raise exception 'BAD_TIME' using errcode='22023'; end if;
 begin
  start_time:=trim(p_start)::time; end_time:=trim(p_end)::time;
 exception when invalid_datetime_format or datetime_field_overflow then
  raise exception 'BAD_TIME' using errcode='22023';
 end;
 if start_time='24:00'::time or end_time='24:00'::time
 then raise exception 'BAD_TIME' using errcode='22023'; end if;
 if start_time=end_time then raise exception 'END_BEFORE_START' using errcode='22023'; end if;
 local_end:=p_day+end_time;
 -- Subtract a calendar date before resolving timezone, including 23/25-hour DST days.
 local_start:=(p_day-case when start_time>end_time then 1 else 0 end)+start_time;
 starts_at:=local_start at time zone zone; ends_at:=local_end at time zone zone;
 if starts_at at time zone zone<>local_start or ends_at at time zone zone<>local_end
 then raise exception 'BAD_TIME' using errcode='22023'; end if;
 if ends_at<=starts_at or ends_at-starts_at<interval '1 minute'
 then raise exception 'END_BEFORE_START' using errcode='22023'; end if;
 if ends_at>nb.calculation_clock() then raise exception 'FUTURE_SLEEP_WINDOW' using errcode='22023'; end if;
 return next;
end $$;

-- Keep stage evidence strictly observed. In particular a reported duration must never
-- fall through the legacy aggregate-as-light fallback and charge the Body Battery.
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.sleep_evidence_minutes(uuid,date)'::regprocedure);
 patched:=replace(def,'and s.wake_at-s.sleep_start<=interval ''48 hours''',
  'and s.wake_at-s.sleep_start<=interval ''48 hours''
  and coalesce(s.raw->>''source'','''')<>''user_reported''');
 if patched=def then raise exception 'SLEEP_BACKFILL_STAGE_NIGHT_ANCHOR_MISSING'; end if;
 def:=patched;
 patched:=replace(def,'and n.total_minutes>0',
  'and n.total_minutes>0 and n.corrected_start is null');
 if patched=def then raise exception 'SLEEP_BACKFILL_FALLBACK_ANCHOR_MISSING'; end if;
 -- Sequential legacy stages must be located on the original intervals before clipping.
 -- Clipping the interval list before assigning offsets shifts every legacy stage.
 def:=patched;
 patched:=replace(def,'greatest(n.sleep_start,nb.bb_instant(j->>''start'')) lo,
         least(n.wake_at,nb.bb_instant(j->>''end'')) hi',
  'greatest(coalesce(nb.bb_instant(n.raw->>''recorded_start''),n.sleep_start),nb.bb_instant(j->>''start'')) lo,
         least(coalesce(nb.bb_instant(n.raw->>''recorded_end''),n.wake_at),nb.bb_instant(j->>''end'')) hi');
 if patched=def then raise exception 'SLEEP_BACKFILL_INTERVAL_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

-- This function locates physiology, not sleep stages. For a user-declared window it
-- includes new edges and original stage gaps, so measured HR/HRV there can be recovered.
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.sleep_windows(uuid,date)'::regprocedure);
 patched:=replace(def,'case when jsonb_typeof(n.raw->''intervals'')=''array'' then n.raw->''intervals''',
  'case when n.corrected_start is not null or n.raw->>''source''=''user_reported''
    then jsonb_build_array(jsonb_build_object(''start'',n.sleep_start,''end'',n.wake_at))
    when jsonb_typeof(n.raw->''intervals'')=''array'' then n.raw->''intervals''');
 if patched=def then raise exception 'SLEEP_BACKFILL_WINDOWS_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

create or replace function nb.sleep_observations(p_user uuid,p_day date,p_domain text)
returns table(ts timestamptz,v numeric)
language sql stable set search_path='' as $$
 with night as materialized (
  select *,nb.merge_sleep_hrv('{}'::jsonb,raw,sleep_start,wake_at) merged
  from public.sleep_nights where user_id=p_user and user_day=p_day
   and nb.sleep_night_is_canonical(p_user,p_day)
 ), windows as materialized (select * from nb.sleep_windows(p_user,p_day)),
 native as materialized (
  select nb.sleep_json_instant(e->>'ts') ts,nb.sleep_json_number(e->>'rmssd_ms') v
  from night n cross join lateral jsonb_array_elements(
   case when p_domain='hrv' and jsonb_typeof(n.merged->'hrv')='array'
    then n.merged->'hrv' else '[]'::jsonb end) e
  where nb.sleep_json_number(e->>'rmssd_ms') between 1 and 300
 ), revoked as materialized (
  select date_bin(interval '1 minute',nb.sleep_json_instant(e->>'ts'),'2000-01-01'::timestamptz) ts
  from night n cross join lateral jsonb_array_elements(
   case when jsonb_typeof(n.merged->'hrv_invalidated')='array'
    then n.merged->'hrv_invalidated' else '[]'::jsonb end) e
 ), candidates as (
  select * from native
  union all
  select r.ts,r.hrv from night n join public.raw_samples r
   on r.user_id=n.user_id and r.ts>=n.sleep_start and r.ts<n.wake_at
  where p_domain='hrv' and r.hrv between 1 and 300
   -- Preserve exact-only legacy nights; only user-declared windows mix sources.
   and (n.corrected_start is not null or n.raw->>'source'='user_reported' or not(n.raw?'hrv'))
   and not exists(select 1 from native x where
    date_bin(interval '1 minute',x.ts,'2000-01-01'::timestamptz)=date_bin(interval '1 minute',r.ts,'2000-01-01'::timestamptz))
   and not exists(select 1 from revoked x where
    x.ts=date_bin(interval '1 minute',r.ts,'2000-01-01'::timestamptz))
  union all
  select r.ts,r.heart::numeric from night n join public.raw_samples r
   on r.user_id=n.user_id and r.ts>=n.sleep_start and r.ts<n.wake_at where p_domain='rhr'
  union all
  select o.ts,o.spo2::numeric from night n join public.oxygen_samples o
   on o.user_id=n.user_id and o.ts>=n.sleep_start and o.ts<n.wake_at where p_domain='spo2'
  union all
  select nb.sleep_json_instant(e->>'ts'),nb.sleep_json_number(e->>'breaths_per_minute')
  from night n cross join lateral jsonb_array_elements(
   case when p_domain='respiration' and jsonb_typeof(n.raw->'respiration')='array'
    then n.raw->'respiration' else '[]'::jsonb end) e
 ), valid as (
  select c.ts,c.v from candidates c where exists(
   select 1 from windows w where c.ts>=w.starts_at and c.ts<w.ends_at)
   and case p_domain when 'hrv' then c.v between 1 and 300
    when 'rhr' then c.v>0 when 'spo2' then c.v between 50 and 100
    when 'respiration' then c.v between 4 and 40 else false end
 ) select valid.ts,percentile_cont(0.5) within group(order by valid.v)::numeric
 from valid group by valid.ts;
$$;

create or replace function nb.corrected_night_totals(p_user uuid,p_user_day date)
returns table(total_minutes smallint,deep_minutes smallint,light_minutes smallint,rem_minutes smallint,wake_count smallint)
language sql stable set search_path='' as $$
 with n as (select greatest(0,floor(extract(epoch from(wake_at-sleep_start))/60))::int minutes
  from public.sleep_nights where user_id=p_user and user_day=p_user_day),
 m as materialized (
  select e.ts,e.stage,row_number() over(order by e.ts) rn,
   coalesce(lag(e.stage) over(order by e.ts),4) prev
  from nb.sleep_evidence_minutes(p_user,p_user_day) e where e.source<>'aggregate_intervals'
 ), runs as (
  select m.*,sum(case when stage=4 and prev<>4 then 1 else 0 end) over(order by ts) wake_run from m
 )
 select greatest(0,n.minutes-(select count(*) from m where stage=4))::smallint,
  case when exists(select 1 from m) then (select count(*) from m where stage=0)::smallint end,
  case when exists(select 1 from m) then (select count(*) from m where stage=1)::smallint end,
  case when exists(select 1 from m) then (select count(*) from m where stage=2)::smallint end,
  case when (select count(*) from m)>=n.minutes then
   (select count(distinct r.wake_run) from runs r where r.stage=4
    and exists(select 1 from runs b where b.stage<>4 and b.rn<r.rn)
    and exists(select 1 from runs a where a.stage<>4 and a.rn>r.rn))::smallint end
 from n;
$$;

-- Keep measured duration and architecture distinct from reported time. The scoring
-- formula still uses reported duration, but cannot treat unknown minutes as light/deep.
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.night_score_parts(uuid,date)'::regprocedure);
 patched:=replace(def,' rec:=nb.weighted_present(array[',
  ' if n.raw->>''source''=''user_reported'' or (n.corrected_start is not null and
    (select count(*) from nb.sleep_evidence_minutes(p_user,p_user_day))
      <floor(extract(epoch from(n.wake_at-n.sleep_start))/60)) then
   arch:=null; deep_pct:=null; light_pct:=null; rem_pct:=null;
  end if;
 rec:=nb.weighted_present(array[');
 if patched=def then raise exception 'SLEEP_BACKFILL_SCORE_ARCH_ANCHOR_MISSING'; end if;
 def:=patched;
 patched:=replace(def,'''duration_basis'',case when n.corrected_start is not null then ''user_corrected'' else ''recorded_segments'' end,''duration_recorded'',1',
  '''duration_basis'',case when n.raw->>''source''=''user_reported'' then ''user_reported''
    when n.corrected_start is not null then ''user_corrected'' else ''recorded_segments'' end,
   ''duration_recorded'',case when n.raw->>''source''=''user_reported'' or
    (n.corrected_start is not null and (select count(*) from nb.sleep_evidence_minutes(p_user,p_user_day))
      <floor(extract(epoch from(n.wake_at-n.sleep_start))/60)) then 0 else 1 end,
   ''unstaged_minutes'',greatest(0,floor(extract(epoch from(n.wake_at-n.sleep_start))/60)-
    (select count(*) from nb.sleep_evidence_minutes(p_user,p_user_day))),
   ''reported_minutes'',case when n.corrected_start is not null or n.raw->>''source''=''user_reported''
    then floor(extract(epoch from(n.wake_at-n.sleep_start))/60) end');
 if patched=def then raise exception 'SLEEP_BACKFILL_SCORE_BASIS_ANCHOR_MISSING'; end if;
 def:=patched;
 patched:=replace(def,' evidence:=evidence||nb.sleep_evidence(p_user,p_user_day,''hrv'')',
  ' if n.corrected_start is not null or n.raw->>''source''=''user_reported'' then
   evidence:=evidence||jsonb_build_object(
    ''sleep_recorded_minutes'',(select count(*) from nb.sleep_evidence_minutes(p_user,p_user_day)),
    ''sleep_gap_minutes'',greatest(0,floor(extract(epoch from(n.wake_at-n.sleep_start))/60)-
      (select count(*) from nb.sleep_evidence_minutes(p_user,p_user_day))));
  end if;
 evidence:=evidence||nb.sleep_evidence(p_user,p_user_day,''hrv'')');
 if patched=def then raise exception 'SLEEP_BACKFILL_RECORDED_MINUTES_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

-- Explicitly label the mixed native/coarse HRV recovered for a declared window.
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.sleep_evidence(uuid,date,text)'::regprocedure);
 patched:=replace(def,'select sleep_start,raw from public.sleep_nights',
  'select sleep_start,raw,corrected_start from public.sleep_nights');
 if patched=def then raise exception 'SLEEP_BACKFILL_EVIDENCE_ANCHOR_MISSING'; end if;
 def:=patched;
 patched:=replace(def,'case when n.raw?''hrv'' then 1 else 0 end',
  'case when n.raw?''hrv'' and n.corrected_start is null and coalesce(n.raw->>''source'','''')<>''user_reported'' then 1 else 0 end');
 patched:=replace(patched,'case when n.raw?''hrv'' then ''exact_minutes'' else ''five_minute_fallback'' end',
  'case when (n.corrected_start is not null or n.raw->>''source''=''user_reported'') and n.raw?''hrv''
   then ''native_with_raw_backfill'' when n.raw?''hrv'' then ''exact_minutes'' else ''five_minute_fallback'' end');
 execute patched;
end $$;

create or replace function nb.sleep_window_receipt(p_user uuid,p_day date)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('user_day',n.user_day,'corrected',n.corrected_start is not null,
  'sleep_start',n.sleep_start,'wake_at',n.wake_at,'corrected_at',n.corrected_at,
  'recorded_start',n.raw->>'recorded_start','recorded_end',n.raw->>'recorded_end',
  'source',coalesce(n.raw->>'source','band'),'total_minutes',n.total_minutes,
  'reported_minutes',floor(extract(epoch from(n.wake_at-n.sleep_start))/60),
  'unstaged_minutes',greatest(0,floor(extract(epoch from(n.wake_at-n.sleep_start))/60)-
    (select count(*) from nb.sleep_evidence_minutes(p_user,p_day))),
  'heart_sample_count',(select count(*) from nb.sleep_observations(p_user,p_day,'rhr')),
  'hrv_sample_count',(select count(*) from nb.sleep_observations(p_user,p_day,'hrv')))
 from public.sleep_nights n where n.user_id=p_user and n.user_day=p_day;
$$;

create or replace function health_commands.create_sleep_window(p_user_day date,p_start text,p_end text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare owner uuid:=auth.uid(); budget jsonb; w record; n public.sleep_nights%rowtype;
begin
 if owner is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if exists(select 1 from public.profiles where user_id=owner and deletion_requested_at is not null)
 then raise exception 'ACCOUNT_DELETING' using errcode='42501'; end if;
 if coalesce((select choice from public.consents where user_id=owner order by decided_at desc,id desc limit 1),'')<>'granted'
 then raise exception 'CONSENT_WITHDRAWN' using errcode='42501'; end if;
 select * into w from nb.resolve_reported_sleep_window(owner,p_user_day,p_start,p_end);
 -- The unique day key is the idempotency key. A retry never turns an insert into an edit.
 perform pg_advisory_xact_lock(hashtextextended(owner::text||':sleep:'||p_user_day::text,0));
 select * into n from public.sleep_nights where user_id=owner and user_day=p_user_day for update;
 if found then
  if n.raw->>'source'='user_reported' and n.sleep_start=w.starts_at and n.wake_at=w.ends_at
  then return nb.sleep_window_receipt(owner,p_user_day); end if;
  raise exception 'SLEEP_NIGHT_EXISTS' using errcode='23505';
 end if;
 budget:=public.consume_request_budget('sleep-correction');
 if not (budget->>'allowed')::boolean then raise exception 'RATE_LIMITED' using errcode='54000'; end if;
 insert into public.sleep_nights(user_id,user_day,sleep_start,wake_at,corrected_start,corrected_end,corrected_at,total_minutes,raw)
 values(owner,p_user_day,w.starts_at,w.ends_at,w.starts_at,w.ends_at,now(),
  floor(extract(epoch from(w.ends_at-w.starts_at))/60)::smallint,
  jsonb_build_object('source','user_reported','line','[]'::jsonb,'intervals','[]'::jsonb))
 on conflict(user_id,user_day) do nothing;
 if not found then raise exception 'SLEEP_NIGHT_EXISTS' using errcode='23505'; end if;
 return nb.sleep_window_receipt(owner,p_user_day);
end $$;

create or replace function health_commands.correct_sleep_window(p_user_day date,p_start text,p_end text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare owner uuid:=auth.uid(); budget jsonb; w record;
begin
 if owner is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if exists(select 1 from public.profiles where user_id=owner and deletion_requested_at is not null)
 then raise exception 'ACCOUNT_DELETING' using errcode='42501'; end if;
 if coalesce((select choice from public.consents where user_id=owner order by decided_at desc,id desc limit 1),'')<>'granted'
 then raise exception 'CONSENT_WITHDRAWN' using errcode='42501'; end if;
 select * into w from nb.resolve_reported_sleep_window(owner,p_user_day,p_start,p_end);
 budget:=public.consume_request_budget('sleep-correction');
 if not (budget->>'allowed')::boolean then raise exception 'RATE_LIMITED' using errcode='54000'; end if;
 perform pg_advisory_xact_lock(hashtextextended(owner::text||':sleep:'||p_user_day::text,0));
 update public.sleep_nights set corrected_start=w.starts_at,corrected_end=w.ends_at,corrected_at=now()
 where user_id=owner and user_day=p_user_day;
 if not found then raise exception 'NO_SLEEP_NIGHT' using errcode='22023'; end if;
 return nb.sleep_window_receipt(owner,p_user_day);
end $$;

-- Match the command boundary used by manual workouts: the Data API wrappers have
-- no elevated privileges; private commands own authorization and the atomic write.
create or replace function public.create_sleep_window(p_user_day date,p_start text,p_end text)
returns jsonb language sql security invoker set search_path='' as $$
 select health_commands.create_sleep_window(p_user_day,p_start,p_end);
$$;
create or replace function public.correct_sleep_window(p_user_day date,p_start text,p_end text)
returns jsonb language sql security invoker set search_path='' as $$
 select health_commands.correct_sleep_window(p_user_day,p_start,p_end);
$$;
revoke all on function health_commands.create_sleep_window(date,text,text),
 health_commands.correct_sleep_window(date,text,text) from public,anon;
grant usage on schema health_commands to service_role;
grant execute on function health_commands.create_sleep_window(date,text,text),
 health_commands.correct_sleep_window(date,text,text) to authenticated,service_role;

revoke all on function nb.resolve_reported_sleep_window(uuid,date,text,text),
 nb.sleep_window_receipt(uuid,date),nb.sleep_observations(uuid,date,text),
 nb.corrected_night_totals(uuid,date) from public,anon,authenticated;
revoke all on function public.create_sleep_window(date,text,text),public.correct_sleep_window(date,text,text) from public,anon;
grant execute on function public.create_sleep_window(date,text,text),public.correct_sleep_window(date,text,text) to authenticated,service_role;
