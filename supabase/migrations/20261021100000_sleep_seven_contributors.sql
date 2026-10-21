create or replace function nb.sleep_contributor_value(p_kind text,p_value numeric)
returns numeric language sql immutable strict set search_path='' as $$
 select case when p_value<0 or p_value::text in ('NaN','Infinity','-Infinity') then null else
 case p_kind
  when 'total_sleep' then nb.score_sleep_duration(p_value)
  when 'efficiency' then case when p_value<=100 then nb.score_window(p_value,50,85,100,null) end
  when 'restfulness' then greatest(0,100-p_value)
  when 'rem' then least(100,p_value/90*100)
  when 'deep' then least(100,p_value/60*100)
  when 'latency' then nb.score_window(p_value,-15,15,20,60)
  when 'timing' then case when p_value<1440 then
   greatest(0,100-least(greatest(p_value-180,0),1440-p_value)/360*100) end
 end end;
$$;

create or replace function nb.night_score_parts(p_user uuid,p_user_day date)
returns table(score numeric,duration_score numeric,architecture_score numeric,
 recovery_score numeric,regularity_score numeric,personal_weight numeric,inputs jsonb)
language plpgsql stable security definer set search_path='' as $$
declare
 n public.sleep_nights%rowtype; v_tz text; measured record; main_window record;
 recorded numeric; elapsed numeric; segments int; asleep numeric; deep_min numeric; rem_min numeric;
 efficiency numeric; rest_penalty numeric; midpoint numeric; dur numeric; total numeric; cap numeric;
 complete boolean; declared boolean; evidence jsonb; scores numeric[]; weights numeric[]:=array[40,10,10,15,15,5,5];
 keys text[]:=array['total_sleep','efficiency','restfulness','rem','deep','latency','timing'];
 i int;
begin
 if not nb.sleep_night_is_canonical(p_user,p_user_day) then return; end if;
 select * into n from public.sleep_nights where user_id=p_user and user_day=p_user_day;
 select coalesce(timezone,'UTC') into v_tz from nb.calculation_profile(p_user,p_user_day);
 v_tz:=coalesce(v_tz,'UTC');
 declared:=n.corrected_start is not null or coalesce(n.raw->>'source'='user_reported',false);
 elapsed:=extract(epoch from(n.wake_at-n.sleep_start))/60;
 select count(*),sum(extract(epoch from(w.ends_at-w.starts_at))/60)
 into segments,recorded from nb.sleep_windows(p_user,p_user_day) w;
 with minutes as materialized (
  select e.ts,e.stage,lag(e.stage) over(order by e.ts) previous,
   lag(e.ts) over(order by e.ts) previous_at
  from nb.sleep_evidence_minutes(p_user,p_user_day) e
  where e.source in ('offset_line','legacy_line')
 )
 select count(*) minutes,count(*) filter(where stage in (0,1,2)) asleep,
  count(*) filter(where stage=0) deep,count(*) filter(where stage=1) light,
  count(*) filter(where stage=2) rem,count(*) filter(where stage in (3,4)) awake,
  count(*) filter(where stage in (3,4) and previous in (0,1,2)
   and ts=previous_at+interval '1 minute'
   and ts<(select max(ts) from minutes where stage in (0,1,2))) wakes
 into measured from minutes;
 complete:=measured.minutes>0 and measured.minutes=recorded
  and (not declared or measured.minutes=elapsed);
 if declared then
  asleep:=greatest(0,elapsed-measured.awake);
 elsif measured.minutes>0 then
  asleep:=measured.asleep;
 elsif n.deep_minutes is not null and n.light_minutes is not null
   and n.deep_minutes+n.light_minutes>0 and n.deep_minutes+n.light_minutes<=n.total_minutes then
  asleep:=n.deep_minutes+n.light_minutes;
 else
  asleep:=n.total_minutes;
 end if;
 if asleep is null or asleep<=0 then return; end if;
 if measured.minutes>0 and (not declared or complete) then
  deep_min:=measured.deep;
  rem_min:=nullif(measured.rem,0);
 elsif not declared and measured.minutes=0 and n.deep_minutes>=0 and n.deep_minutes<=asleep then
  deep_min:=n.deep_minutes;
 end if;
 if complete then
  efficiency:=100.0*measured.asleep/measured.minutes;
  rest_penalty:=least(100,100.0*measured.awake/measured.minutes*2
   +greatest(0,measured.wakes-1)*10);
 end if;
 select w.starts_at,w.ends_at into main_window from nb.sleep_windows(p_user,p_user_day) w
 order by w.ends_at-w.starts_at desc,w.starts_at limit 1;
 if main_window.starts_at is not null then
  midpoint:=extract(epoch from(
   (main_window.starts_at+(main_window.ends_at-main_window.starts_at)/2)
    at time zone v_tz)::time)/60;
 end if;
 scores:=array[
  nb.sleep_contributor_value('total_sleep',asleep),
  nb.sleep_contributor_value('efficiency',efficiency),
  nb.sleep_contributor_value('restfulness',rest_penalty),
  nb.sleep_contributor_value('rem',rem_min),
  nb.sleep_contributor_value('deep',deep_min),
  null,
  nb.sleep_contributor_value('timing',midpoint)];
 dur:=scores[1];
 total:=nb.weighted_present(scores,weights);
 cap:=nb.sleep_duration_score_cap(asleep);
 evidence:=jsonb_strip_nulls(jsonb_build_object(
  'contributor_policy',3,'duration_min',floor(asleep)::int,
  'duration_recorded',case when not declared and measured.minutes>0 then 1 else 0 end,
  'duration_basis',case when n.raw->>'source'='user_reported' then 'user_reported'
   when declared then 'user_corrected'
   when measured.minutes>0 then 'measured_asleep_minutes' else 'aggregate_estimate' end,
  'sleep_segment_count',segments,'sleep_recorded_minutes',measured.minutes,
  'sleep_elapsed_minutes',floor(elapsed)::int,'sleep_gap_minutes',floor(greatest(0,elapsed-coalesce(recorded,0)))::int,
  'unstaged_minutes',floor(greatest(0,coalesce(recorded,elapsed,0)-measured.minutes))::int,
  'stage_coverage',measured.minutes/nullif(coalesce(recorded,elapsed),0),
  'reported_minutes',case when declared then floor(elapsed)::int end,
  'efficiency_pct',round(efficiency,2),'efficiency_recorded_only',1,
  'restfulness_wakes_only',1,'awake_min',case when measured.minutes>0 then measured.awake end,
  'wakes',case when complete then measured.wakes end,
  'deep_min',deep_min,'deep_pct',round(100*deep_min/asleep,1),
  'light_pct',case when measured.minutes>0 and (not declared or complete) then round(100.0*measured.light/asleep,1) end,
  'rem_min',rem_min,'rem_pct',round(100*rem_min/asleep,1),
  'bed_offset',nb.evening_offset(n.sleep_start,v_tz),'midpoint_min',round(midpoint,1),
  'timing_population_reference',1,'latency_available',0,
  'score_before_duration_cap',round(total,2),'duration_score_cap',round(cap,2),
  'duration_cap_applied',case when round(total)>round(cap) then 1 else 0 end));
 for i in 1..7 loop
  evidence:=evidence||jsonb_build_object('weight_'||keys[i],weights[i]);
  if scores[i] is not null then
   evidence:=evidence||jsonb_build_object('score_'||keys[i],round(scores[i],2));
  end if;
 end loop;
 return query select round(least(total,cap)),round(dur),null::numeric,null::numeric,
  null::numeric,0::numeric,evidence;
end $$;

revoke execute on function nb.sleep_contributor_value(text,numeric),
 nb.night_score_parts(uuid,date) from public,anon,authenticated;

do $$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('nb.refresh_night_score(uuid,date)'::regprocedure);
 patched:=replace(definition,'''sleep-v2.0''','''sleep-v3.0''');
 if patched=definition then raise exception 'SLEEP_V3_VERSION_ANCHOR_MISSING'; end if;
 execute patched;

 definition:=pg_get_functiondef('nb.training_recovery_target(uuid,date,smallint)'::regprocedure);
 patched:=replace(definition,
  '   sleep_readiness:=nb.weighted_present(array[score.duration_score,score.recovery_score,
    score.architecture_score,score.regularity_score]::numeric[],array[40,40,10,10]::numeric[]);',
  '   if score.inputs->>''contributor_policy''=''3'' then
    sleep_readiness:=score.score;
   else
    sleep_readiness:=nb.weighted_present(array[score.duration_score,score.recovery_score,
     score.architecture_score,score.regularity_score]::numeric[],array[40,40,10,10]::numeric[]);
   end if;');
 if patched=definition then raise exception 'SLEEP_V3_TRAINING_SCORE_ANCHOR_MISSING'; end if;
 definition:=patched;
 patched:=replace(definition,
  '   limited:=score.recovery_score is null or score.personal_weight<1 or p_wake is null;',
  '   limited:=case when score.inputs->>''contributor_policy''=''3'' then
    not(score.inputs ?& array[''score_total_sleep'',''score_efficiency'',''score_restfulness'',
     ''score_rem'',''score_deep'',''score_timing'']) or p_wake is null
    else score.recovery_score is null or score.personal_weight<1 or p_wake is null end;');
 if patched=definition then raise exception 'SLEEP_V3_TRAINING_COVERAGE_ANCHOR_MISSING'; end if;
 definition:=patched;
 patched:=replace(definition,'''version'',''target-1.0''',
  '''version'',case when score.inputs->>''contributor_policy''=''3'' then ''target-1.1'' else ''target-1.0'' end');
 if patched=definition then raise exception 'SLEEP_V3_TRAINING_VERSION_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

do $$
declare r record;
begin
 for r in select d.user_id,min(d.user_day) user_day
  from public.daily_results d join (
   select user_id,user_day from public.sleep_nights
   union select user_id,user_day from public.night_score
  ) s on s.user_id=d.user_id and s.user_day=d.user_day
  group by d.user_id order by d.user_id
 loop
  perform nb.invalidate_calculation(r.user_id,r.user_day);
 end loop;
 for r in select user_id,user_day from public.sleep_nights
   union select user_id,user_day from public.night_score order by user_id,user_day
 loop
  perform nb.refresh_night_score(r.user_id,r.user_day);
 end loop;
end $$;
