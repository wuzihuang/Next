create or replace function nb.sleep_duration_score_cap(p_minutes numeric)
returns numeric language sql immutable strict set search_path='' as $$
 select case
  when p_minutes<=240 then greatest(0,p_minutes/6)
  when p_minutes<300 then 40+(p_minutes-240)/3
  when p_minutes<420 then 60+(p_minutes-300)/4
  when p_minutes<450 then 90+(p_minutes-420)/3
  else 100
 end;
$$;

revoke execute on function nb.sleep_duration_score_cap(numeric) from public,anon,authenticated;

do $$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('nb.night_score_parts(uuid,date)'::regprocedure);
 patched:=replace(definition,'total numeric; evidence jsonb;',
  'total numeric; duration_cap numeric; group_weights numeric[]:=array[50,20,20,10]; evidence jsonb;');
 if patched=definition then raise exception 'SLEEP_V2_DECLARATION_ANCHOR_MISSING'; end if;
 definition:=patched;

 patched:=replace(definition,
  'total:=nb.weighted_present(array[dur,arch,rec,reg],array[25,25,35,15]);',
  'total:=nb.weighted_present(array[dur,arch,rec,reg],group_weights);
 duration_cap:=nb.sleep_duration_score_cap(n.total_minutes);');
 if patched=definition then raise exception 'SLEEP_V2_WEIGHTS_ANCHOR_MISSING'; end if;
 definition:=patched;

 patched:=replace(definition,' return query select round(total),round(dur),',
  ' evidence:=evidence||jsonb_build_object(
   ''weight_duration'',group_weights[1],''weight_architecture'',group_weights[2],
   ''weight_recovery'',group_weights[3],''weight_regularity'',group_weights[4],
   ''score_before_duration_cap'',round(total,2),''duration_score_cap'',round(duration_cap,2),
   ''duration_cap_applied'',case when round(total)>round(duration_cap) then 1 else 0 end);
 total:=least(total,duration_cap);
 return query select round(total),round(dur),');
 if patched=definition then raise exception 'SLEEP_V2_TOTAL_ANCHOR_MISSING'; end if;
 execute patched;

 definition:=pg_get_functiondef('nb.refresh_night_score(uuid,date)'::regprocedure);
 patched:=replace(definition,'''sleep-v1.3''','''sleep-v2.0''');
 if patched=definition then raise exception 'SLEEP_V2_VERSION_ANCHOR_MISSING'; end if;
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
   union select user_id,user_day from public.night_score
   order by user_id,user_day
 loop
  perform nb.refresh_night_score(r.user_id,r.user_day);
 end loop;
end $$;
