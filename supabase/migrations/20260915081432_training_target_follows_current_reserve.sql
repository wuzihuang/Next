-- Compose the independently published sleep/recovery recommendation with bb-3.0.
-- Preserve the base model and its evidence; a current reserve only limits it.
do $$ declare definition text; begin
 definition:=pg_get_functiondef('nb.training_target(uuid,date,smallint)'::regprocedure);
 if position('target-1.0' in definition)=0 then raise exception 'TRAINING_BASE_TARGET_ANCHOR_MISSING'; end if;
 definition:=replace(definition,'FUNCTION nb.training_target(', 'FUNCTION nb.training_recovery_target(');
 execute definition;
end $$;

create or replace function nb.training_target(p_user uuid,p_user_day date,p_wake smallint)
returns jsonb language plpgsql stable set search_path='' as $$
declare base jsonb; reserve record; limit_info jsonb; proposed numeric; final_target numeric; load numeric;
begin
 base:=nb.training_recovery_target(p_user,p_user_day,p_wake);
 select * into reserve from nb.training_reserve(p_user,p_user_day);
 limit_info:=reserve.drivers->'training_target';
 proposed:=(base->>'target')::numeric;
 -- Preserve the sleep-led base and the last observed reserve limit. Stale evidence
 -- must never silently lift a fatigue restriction; expose its original clock.
 final_target:=proposed;
 if proposed is not null and (limit_info->>'value')::numeric is not null then
  final_target:=least(proposed,(limit_info->>'value')::numeric);
 end if;
 select t.training_load into load from nb.compute_training(p_user,p_user_day) t;
 return base||jsonb_build_object('version','target-1.1','base_target',proposed,
  'target',final_target,'lower',case when final_target is not null then greatest(0,final_target-2) end,
  'upper',case when final_target is not null then least(20,final_target+2) end,
  'current_reserve',reserve.current_value,'reserve_limit',limit_info->'value','reserve_fresh',coalesce((limit_info->>'fresh')::boolean,false),
  'remaining',case when final_target is not null and load is not null then greatest(0,final_target-load) end,
  'observed_at',limit_info->'observed_at','reserve_estimated',reserve.drivers->'assumed_anchor',
  'limited',coalesce((base->>'limited')::boolean,true) or coalesce((reserve.drivers->>'assumed_anchor')::boolean,true),
  'reserve_adjustment',case when final_target is not null then final_target-proposed end);
end;
$$;

-- Version the combined result so old training targets do not remain current.
do $$ declare definition text; patched text; begin
 definition:=pg_get_functiondef('nb.calculation_version()'::regprocedure);
 patched:=replace(definition,'/calc-1','/target-1.1/calc-1');
 if patched=definition then raise exception 'DYNAMIC_TARGET_VERSION_ANCHOR_MISSING'; end if;
 execute patched;
end $$;
select nb.invalidate_calculation(user_id,min(user_day)) from public.daily_results group by user_id;
revoke all on function nb.training_recovery_target(uuid,date,smallint),nb.training_target(uuid,date,smallint)
 from public,anon,authenticated;
