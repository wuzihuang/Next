create table public.mcp_meal_requests (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id text not null,
  request_id uuid not null,
  request jsonb not null,
  receipt jsonb not null,
  primary key (user_id, client_id, request_id)
);
alter table public.mcp_meal_requests enable row level security;
revoke all on public.mcp_meal_requests from public, anon, authenticated;

create function public.log_mcp_meal(
  p_request_id uuid, p_items jsonb, p_eaten_at timestamptz default null,
  p_slot text default null, p_confidence text default 'MEDIUM'
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_client text := nullif(auth.jwt()->>'client_id','');
  v_grant public.mcp_grants%rowtype;
  v_request jsonb;
  v_existing public.mcp_meal_requests%rowtype;
  v_tz text;
  v_time timestamptz;
  v_day date;
  v_slot text;
  v_hour integer;
  v_group uuid;
  v_items jsonb;
  v_receipt jsonb;
begin
  if v_user is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  if v_client is null then raise exception 'OAUTH_CLIENT_ONLY' using errcode='42501'; end if;
  select * into v_grant from public.mcp_grants
    where user_id=v_user and client_id=v_client and revoked_at is null for share;
  if not found then raise exception 'MCP_GRANT_MISSING' using errcode='42501'; end if;
  if not v_grant.can_write then raise exception 'MCP_WRITE_NOT_GRANTED' using errcode='42501'; end if;
  if exists(select 1 from public.profiles where user_id=v_user and deletion_requested_at is not null) then
    raise exception 'ACCOUNT_DELETING' using errcode='42501';
  end if;
  if coalesce((select choice from public.consents where user_id=v_user order by decided_at desc,id desc limit 1),'') <> 'granted' then
    raise exception 'CONSENT_WITHDRAWN' using errcode='42501';
  end if;
  if p_request_id is null or p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'INVALID_MEAL_REQUEST' using errcode='22023';
  end if;
  if jsonb_array_length(p_items) not between 1 and 12 or octet_length(p_items::text)>60000
    or p_confidence is null or p_confidence not in ('LOW','MEDIUM','HIGH')
    or (p_slot is not null and p_slot not in ('BREAKFAST','LUNCH','DINNER','SNACK')) then
    raise exception 'INVALID_MEAL_REQUEST' using errcode='22023';
  end if;
  v_request := jsonb_build_object('items',p_items,'eaten_at',p_eaten_at,'slot',p_slot,'confidence',p_confidence);
  perform pg_advisory_xact_lock(hashtextextended(v_user::text || ':meals',0));
  select * into v_existing from public.mcp_meal_requests
    where user_id=v_user and client_id=v_client and request_id=p_request_id;
  if found then
    if v_existing.request <> v_request then raise exception 'OPERATION_CONFLICT' using errcode='23505'; end if;
    return v_existing.receipt || '{"replay":true}'::jsonb;
  end if;
  select coalesce(timezone,'UTC') into v_tz from public.profiles where user_id=v_user;
  v_tz := coalesce(v_tz,'UTC');
  v_time := coalesce(p_eaten_at,now());
  v_day := nb.user_day_of(v_time,v_tz);
  if not isfinite(v_time) or v_time > now()+interval '5 minutes'
    or v_day not between nb.user_day_of(now(),v_tz)-6 and nb.user_day_of(now(),v_tz) then
    raise exception 'INVALID_MEAL_TIME' using errcode='22023';
  end if;
  v_hour := extract(hour from v_time at time zone v_tz);
  v_slot := coalesce(p_slot,case when v_hour>=4 and v_hour<11 then 'BREAKFAST'
    when v_hour>=11 and v_hour<15 then 'LUNCH'
    when v_hour>=15 and v_hour<21 then 'DINNER' else 'SNACK' end);
  if exists(select 1 from jsonb_array_elements(p_items) item where jsonb_typeof(item)<>'object') then
    raise exception 'INVALID_MEAL_REQUEST' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_items) item, jsonb_object_keys(item) k
    where k not in ('name','portion','kcal','protein_g','carb_g','fat_g','fiber_g','sugar_g','sodium_mg')) then
    raise exception 'INVALID_MEAL_REQUEST' using errcode='22023';
  end if;
  select jsonb_agg(item || jsonb_build_object(
    'user_day',v_day,'slot',v_slot,'logged_at',v_time,'confidence',p_confidence,
    'model_version',left('mcp:' || coalesce(nullif(v_grant.client_name,''),v_client),256)) order by ord)
    into v_items from jsonb_array_elements(p_items) with ordinality items(item,ord);
  v_group := md5(v_user::text || ':mcp:' || v_client || ':' || p_request_id::text)::uuid;
  v_receipt := public.apply_meal_plate(v_group,v_items) || jsonb_build_object(
    'plate_id',v_group,'day',v_day,'slot',v_slot,
    'total_kcal',(select sum((item->>'kcal')::numeric) from jsonb_array_elements(v_items) item));
  insert into public.mcp_meal_requests(user_id,client_id,request_id,request,receipt)
    values(v_user,v_client,p_request_id,v_request,v_receipt);
  return v_receipt;
end $$;
revoke all on function public.log_mcp_meal(uuid,jsonb,timestamptz,text,text) from public,anon;
grant execute on function public.log_mcp_meal(uuid,jsonb,timestamptz,text,text) to authenticated;

create function public.mcp_health_profile()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('timezone',timezone,'sex',sex,'birthDate',birth_date,
    'heightCm',height_cm,'goal',goal,'unitsMetric',units_metric,'locale',locale)
  from public.profiles where user_id=(select auth.uid())
$$;
revoke all on function public.mcp_health_profile() from public,anon;
grant execute on function public.mcp_health_profile() to authenticated;

grant select on public.reserve_samples to authenticated;

do $$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('public.mcp_request_gate()'::regprocedure);
  patched := replace(definition,'''/rpc/apply_meal_plate'',', '''/rpc/log_mcp_meal'', ''/rpc/apply_meal_plate'',');
  if patched=definition then raise exception 'MCP_WRITE_GATE_ANCHOR_MISSING'; end if;
  definition := patched;
  patched := replace(definition,'''/oxygen_samples'', ''/raw_samples'', ''/meals''',
    '''/oxygen_samples'', ''/raw_samples'', ''/meals'', ''/response_samples'', ''/balance_checks'',
    ''/sport_session_recaps'', ''/manual_sport_sessions'', ''/sport_heart_rate_samples'',
    ''/sport_energy_samples'', ''/reserve_samples'', ''/night_hrv''');
  if patched=definition then raise exception 'MCP_READ_GATE_ANCHOR_MISSING'; end if;
  definition := patched;
  patched := replace(definition,'''/rpc/touch_mcp_grant'',', '''/rpc/mcp_health_profile'', ''/rpc/touch_mcp_grant'',');
  if patched=definition then raise exception 'MCP_PROFILE_GATE_ANCHOR_MISSING'; end if;
  execute patched;
end $$;
notify pgrst,'reload schema';
