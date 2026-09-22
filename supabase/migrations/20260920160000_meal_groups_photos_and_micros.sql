-- 一次估算是一盘饭。模型本来就把一盘拆成若干 item（meal-estimate 的 system prompt:
-- "One visible food is one item"），每一项写成独立的一行 meal —— 这个形态保留，日档食物表
-- 仍然不分餐。缺的是「这一次拍的这盘」这个聚合：三条共享 meal_group_id，照片和份量挂在组上，
-- 于是整体回看、整体调份量、整体存成常吃才有落点。
--
-- portion 一直都在模型的输出里（MealItemSchema.portion, "1 bowl" / "200 g"），只是从来没有
-- 落库，用户想改份量就只能重打一遍数字。这里把它接上。
--
-- 微量三项（纤维 / 糖 / 钠）缺就是 null。和 kcal 一样，0 不是「没测到」的写法。

alter table public.meals
  add column if not exists meal_group_id uuid,
  add column if not exists portion       text,
  add column if not exists photo_path    text,
  add column if not exists fiber_g       integer,
  add column if not exists sugar_g       integer,
  add column if not exists sodium_mg     integer;

alter table public.meals
  add constraint meals_portion_len    check (portion is null or length(portion) between 1 and 64),
  add constraint meals_photo_path_len check (photo_path is null or length(photo_path) between 1 and 512),
  add constraint meals_photo_path_own check (photo_path is null or photo_path like user_id::text || '/%'),
  add constraint meals_fiber_nonneg   check (fiber_g   is null or fiber_g   between 0 and 100000),
  add constraint meals_sugar_nonneg   check (sugar_g   is null or sugar_g   between 0 and 100000),
  add constraint meals_sodium_nonneg  check (sodium_mg is null or sodium_mg between 0 and 100000);

create index meals_group_idx on public.meals (user_id, meal_group_id)
  where deleted_at is null and meal_group_id is not null;

-- The append-only trigger compares every column by name. A column it does not know about
-- would be silently mutable from the client, so the three new ones join the tuple.
create or replace function public.meals_only_soft_delete()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (new.id, new.user_id, new.user_day, new.slot, new.logged_at, new.text_input,
      new.kcal, new.protein_g, new.carb_g, new.fat_g, new.confidence,
      new.model_version, new.client_op_id,
      new.meal_group_id, new.portion, new.photo_path, new.fiber_g, new.sugar_g, new.sodium_mg)
     is distinct from
     (old.id, old.user_id, old.user_day, old.slot, old.logged_at, old.text_input,
      old.kcal, old.protein_g, old.carb_g, old.fat_g, old.confidence,
      old.model_version, old.client_op_id,
      old.meal_group_id, old.portion, old.photo_path, old.fiber_g, old.sugar_g, old.sodium_mg)
  then
    raise exception 'meals is append-only: an edit is a soft delete plus a new row';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------- 常吃

-- 一份存下来的餐（一组 item），再记一次就是把 items 重放成新的一组 meal 行。
-- 它不是 meals 的外键：删掉那顿饭不该删掉这份收藏，改掉这份收藏也不该改历史。
create table public.meal_favorites (
  id           uuid primary key default extensions.gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  label        text not null check (length(label) between 1 and 120),
  items        jsonb not null,
  photo_path   text check (photo_path is null or length(photo_path) between 1 and 512),
  created_at   timestamptz not null default now(),
  last_used_at timestamptz,
  uses         integer not null default 0 check (uses >= 0),
  check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 12)
);
create index meal_favorites_owner on public.meal_favorites (user_id, last_used_at desc nulls last);
alter table public.meal_favorites enable row level security;
grant select, insert, update, delete on public.meal_favorites to authenticated;

create policy meal_favorites_select on public.meal_favorites
  for select to authenticated using ((select auth.uid()) = user_id);
create policy meal_favorites_insert on public.meal_favorites
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy meal_favorites_update on public.meal_favorites
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy meal_favorites_delete on public.meal_favorites
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------- 餐照片

-- 私有桶，路径第一段是 user id，客户端用自己的 JWT 直传直读；服务端不做中转。
-- split_part 而不是 storage.foldername：本地验证栈的 storage 是个桩，没有那个函数。
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('meal-photos', 'meal-photos', false, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy meal_photo_read on storage.objects for select to authenticated using (
  bucket_id = 'meal-photos' and split_part(name, '/', 1) = (select auth.uid())::text);
create policy meal_photo_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'meal-photos' and split_part(name, '/', 1) = (select auth.uid())::text);
create policy meal_photo_delete on storage.objects for delete to authenticated using (
  bucket_id = 'meal-photos' and split_part(name, '/', 1) = (select auth.uid())::text);

-- ---------------------------------------------------------------- 写入路径

-- 与 20260906220000 的定义一致，只多了六个可选字段：它们随 create / amend 一起落行，
-- 缺席就是 null，显式 null 视为格式错误（客户端省略即可）。
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
      or (v_row->>'kcal')::numeric not between 1 and 100000
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
