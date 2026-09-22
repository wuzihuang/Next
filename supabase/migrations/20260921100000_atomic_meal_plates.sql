-- A photo is one transaction: a failed food row rolls back the whole plate.
-- Zero kcal is an explicit estimate (water, unsweetened drinks), not missing data.
alter table public.meals drop constraint meals_kcal_check;
alter table public.meals add constraint meals_kcal_check check (kcal is null or kcal >= 0);

create or replace function public.apply_meal_operation(
  p_operation_id uuid, p_kind text, p_meal_id uuid, p_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_existing public.meal_operations%rowtype;
  v_meal public.meals%rowtype;
  v_target uuid;
  v_row jsonb;
  v_today date;
  v_zone text;
  v_logged_at timestamptz;
begin
  if v_user is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  if exists (select 1 from public.profiles where user_id=v_user and deletion_requested_at is not null)
    then raise exception 'ACCOUNT_DELETING' using errcode='42501'; end if;
  if p_operation_id is null or p_meal_id is null or p_kind not in ('create','amend','delete')
    or p_kind is null or p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'INVALID_OPERATION' using errcode='22023';
  end if;
  -- Withdrawal stops new collection and amendments. Explicit removal remains available.
  if p_kind <> 'delete' and coalesce((select choice from public.consents
    where user_id=v_user order by decided_at desc,id desc limit 1),'') <> 'granted' then
    raise exception 'CONSENT_WITHDRAWN' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text || ':meals', 0));
  select * into v_existing from public.meal_operations
    where user_id=v_user and operation_id=p_operation_id;
  if found then
    if v_existing.kind <> p_kind or v_existing.meal_id <> p_meal_id or v_existing.payload <> p_payload then
      raise exception 'OPERATION_CONFLICT' using errcode='23505';
    end if;
    return jsonb_build_object('operation_id',p_operation_id,'client_op_id',p_operation_id,
      'meal_id',p_meal_id,'id',case when p_kind='amend' then (p_payload->>'id')::uuid else p_meal_id end,'replay',true);
  end if;
  if p_kind in ('amend','delete') then
    select * into v_meal from public.meals where user_id=v_user and id=p_meal_id for update;
    if not found then raise exception 'MEAL_NOT_FOUND' using errcode='P0002'; end if;
    select coalesce(timezone,'UTC') into v_zone from public.profiles where user_id=v_user;
    v_today := nb.user_day_of(now(),coalesce(v_zone,'UTC'));
    if v_meal.user_day < v_today-6 or v_meal.user_day > v_today then
      raise exception 'MEAL_EDIT_WINDOW_CLOSED' using errcode='22023';
    end if;
    if p_kind='amend' and v_meal.deleted_at is not null then
      raise exception 'MEAL_ALREADY_DELETED' using errcode='22023';
    end if;
  end if;
  if p_kind in ('create','amend') then
    v_row := p_payload;
    v_target := case when p_kind='create' then p_meal_id else (v_row->>'id')::uuid end;
    if v_target is null or (p_kind='amend' and v_target=p_meal_id)
      or jsonb_typeof(v_row->'user_day') is distinct from 'string'
      or jsonb_typeof(v_row->'slot') is distinct from 'string'
      or jsonb_typeof(v_row->'name') is distinct from 'string'
      or jsonb_typeof(v_row->'kcal') is distinct from 'number'
      or coalesce(v_row->>'slot','') not in ('BREAKFAST','LUNCH','DINNER','SNACK')
      or coalesce(v_row->>'kcal','') !~ '^[0-9]+$'
      or (v_row->>'kcal')::numeric not between 0 and 100000
      or length(coalesce(v_row->>'name','')) not between 1 and 8000
      or coalesce(v_row->>'confidence','MEDIUM') not in ('LOW','MEDIUM','HIGH')
      or length(coalesce(v_row->>'model_version','')) > 256 then
      raise exception 'INVALID_MEAL' using errcode='22023';
    end if;
    if exists(select 1 from jsonb_each(v_row) e where e.key in ('protein_g','carb_g','fat_g','fiber_g','sugar_g','sodium_mg')
      and (jsonb_typeof(e.value) <> 'number' or e.value::text !~ '^[0-9]+$'
        or (case when jsonb_typeof(e.value)='number' then e.value::text::numeric else -1 end) not between 0 and 100000)) then
      raise exception 'INVALID_MEAL' using errcode='22023';
    end if;
    if (v_row ? 'portion' and (jsonb_typeof(v_row->'portion') is distinct from 'string'
          or length(v_row->>'portion') not between 1 and 64))
      or (v_row ? 'photo_path' and (jsonb_typeof(v_row->'photo_path') is distinct from 'string'
          or length(v_row->>'photo_path') not between 1 and 512
          or v_row->>'photo_path' not like v_user::text || '/%'))
      or (v_row ? 'meal_group_id' and (jsonb_typeof(v_row->'meal_group_id') is distinct from 'string'
          or v_row->>'meal_group_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) then
      raise exception 'INVALID_MEAL' using errcode='22023';
    end if;
    if v_row ? 'logged_at' and jsonb_typeof(v_row->'logged_at') is distinct from 'string' then
      raise exception 'INVALID_MEAL' using errcode='22023';
    end if;
    begin
      v_logged_at := coalesce((v_row->>'logged_at')::timestamptz, now());
    exception when others then
      raise exception 'INVALID_MEAL' using errcode='22023';
    end;
    if p_kind='amend' and (v_row->>'user_day')::date <> v_meal.user_day then
      raise exception 'MEAL_DAY_CHANGED' using errcode='22023';
    end if;
    -- Legacy create retries get an acknowledgment only if the accepted payload matches.
    if p_kind='create' then
      select * into v_meal from public.meals where user_id=v_user and client_op_id=p_operation_id;
      if found then
        if v_meal.id <> v_target or v_meal.user_day <> (v_row->>'user_day')::date
          or v_meal.slot <> v_row->>'slot' or v_meal.kcal is distinct from (v_row->>'kcal')::integer
          or v_meal.text_input is distinct from v_row->>'name'
          or v_meal.protein_g is distinct from (v_row->>'protein_g')::integer
          or v_meal.carb_g is distinct from (v_row->>'carb_g')::integer
          or v_meal.fat_g is distinct from (v_row->>'fat_g')::integer
          or v_meal.model_version is distinct from v_row->>'model_version'
          or v_meal.confidence is distinct from coalesce(v_row->>'confidence','MEDIUM')
          or v_meal.meal_group_id is distinct from (v_row->>'meal_group_id')::uuid
          or v_meal.portion is distinct from v_row->>'portion'
          or v_meal.photo_path is distinct from v_row->>'photo_path'
          or v_meal.fiber_g is distinct from (v_row->>'fiber_g')::integer
          or v_meal.sugar_g is distinct from (v_row->>'sugar_g')::integer
          or v_meal.sodium_mg is distinct from (v_row->>'sodium_mg')::integer then
          raise exception 'OPERATION_CONFLICT' using errcode='23505';
        end if;
      else
        insert into public.meals(id,user_id,user_day,slot,text_input,kcal,protein_g,carb_g,fat_g,
          confidence,model_version,client_op_id,logged_at,
          meal_group_id,portion,photo_path,fiber_g,sugar_g,sodium_mg)
        values(v_target,v_user,(v_row->>'user_day')::date,v_row->>'slot',v_row->>'name',
          (v_row->>'kcal')::integer,(v_row->>'protein_g')::integer,(v_row->>'carb_g')::integer,
          (v_row->>'fat_g')::integer,coalesce(v_row->>'confidence','MEDIUM'),v_row->>'model_version',
          p_operation_id,v_logged_at,
          (v_row->>'meal_group_id')::uuid,v_row->>'portion',v_row->>'photo_path',
          (v_row->>'fiber_g')::integer,(v_row->>'sugar_g')::integer,(v_row->>'sodium_mg')::integer);
      end if;
    else
      update public.meals set deleted_at=coalesce(deleted_at,now()) where user_id=v_user and id=p_meal_id;
      insert into public.meals(id,user_id,user_day,slot,text_input,kcal,protein_g,carb_g,fat_g,
        confidence,model_version,client_op_id,logged_at,
        meal_group_id,portion,photo_path,fiber_g,sugar_g,sodium_mg)
      values(v_target,v_user,(v_row->>'user_day')::date,v_row->>'slot',v_row->>'name',
        (v_row->>'kcal')::integer,(v_row->>'protein_g')::integer,(v_row->>'carb_g')::integer,
        (v_row->>'fat_g')::integer,coalesce(v_row->>'confidence','MEDIUM'),v_row->>'model_version',
        p_operation_id,v_logged_at,
        (v_row->>'meal_group_id')::uuid,v_row->>'portion',v_row->>'photo_path',
        (v_row->>'fiber_g')::integer,(v_row->>'sugar_g')::integer,(v_row->>'sodium_mg')::integer);
    end if;
  else
    v_target := p_meal_id;
    update public.meals set deleted_at=coalesce(deleted_at,now()) where user_id=v_user and id=p_meal_id;
  end if;
  insert into public.meal_operations(user_id,operation_id,kind,meal_id,payload)
    values(v_user,p_operation_id,p_kind,p_meal_id,p_payload);
  return jsonb_build_object('operation_id',p_operation_id,'client_op_id',p_operation_id,
    'meal_id',p_meal_id,'id',v_target,'replay',false);
end;
$$;
revoke all on function public.apply_meal_operation(uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.apply_meal_operation(uuid,text,uuid,jsonb) to authenticated;


create table public.meal_plate_operations (
  user_id uuid not null references auth.users(id) on delete cascade,
  group_id uuid not null,
  items jsonb not null,
  meal_ids jsonb not null,
  primary key (user_id, group_id)
);
alter table public.meal_plate_operations enable row level security;
revoke all on public.meal_plate_operations from public, anon, authenticated;

create or replace function public.apply_meal_plate(p_group_id uuid, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_existing public.meal_plate_operations%rowtype;
  v_item jsonb;
  v_index integer := 0;
  v_id uuid;
  v_operation uuid;
  v_ids jsonb := '[]'::jsonb;
begin
  if v_user is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  if exists (select 1 from public.profiles where user_id=v_user and deletion_requested_at is not null)
    then raise exception 'ACCOUNT_DELETING' using errcode='42501'; end if;
  if coalesce((select choice from public.consents where user_id=v_user
    order by decided_at desc,id desc limit 1),'') <> 'granted' then
    raise exception 'CONSENT_WITHDRAWN' using errcode='42501';
  end if;
  if p_group_id is null or p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'INVALID_MEAL_PLATE' using errcode='22023';
  end if;
  if jsonb_array_length(p_items) not between 1 and 12 then
    raise exception 'INVALID_MEAL_PLATE' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text || ':meals', 0));
  select * into v_existing from public.meal_plate_operations
    where user_id=v_user and group_id=p_group_id;
  if found then
    if v_existing.items <> p_items then
      raise exception 'OPERATION_CONFLICT' using errcode='23505';
    end if;
    return jsonb_build_object('meal_ids',v_existing.meal_ids,'replay',true);
  end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'INVALID_MEAL_PLATE' using errcode='22023';
    end if;
    v_id := md5(v_user::text || ':' || p_group_id::text || ':row:' || v_index::text)::uuid;
    v_operation := md5(v_user::text || ':' || p_group_id::text || ':operation:' || v_index::text)::uuid;
    perform public.apply_meal_operation(v_operation,'create',v_id,
      v_item || jsonb_build_object('meal_group_id',p_group_id));
    v_ids := v_ids || jsonb_build_array(v_id);
    v_index := v_index + 1;
  end loop;
  insert into public.meal_plate_operations(user_id,group_id,items,meal_ids)
    values(v_user,p_group_id,p_items,v_ids);
  return jsonb_build_object('meal_ids',v_ids,'replay',false);
end;
$$;
revoke all on function public.apply_meal_plate(uuid,jsonb) from public,anon;
grant execute on function public.apply_meal_plate(uuid,jsonb) to authenticated;
