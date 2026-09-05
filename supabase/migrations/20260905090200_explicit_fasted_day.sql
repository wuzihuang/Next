-- A fasting day is an explicit user fact, independent of derived daily_results.
create table public.fasted_days (
 user_id uuid not null references auth.users(id) on delete cascade,
 user_day date not null,
 confirmed_at timestamptz not null default now(),
 primary key(user_id,user_day)
);
alter table public.fasted_days enable row level security;
revoke all on public.fasted_days from anon,authenticated;
grant select on public.fasted_days to authenticated;
create policy fasted_days_read on public.fasted_days for select to authenticated
 using ((select auth.uid())=user_id);
create trigger calculation_fact_changed after insert or update or delete on public.fasted_days
 for each row execute function nb.on_calculation_fact();

create function public.mark_day_fasted(p_day date, p_clear_existing boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare owner uuid:=auth.uid(); zone text; budget jsonb;
begin
 if owner is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if exists(select 1 from public.profiles where user_id=owner and deletion_requested_at is not null)
 then raise exception 'ACCOUNT_DELETING' using errcode='42501'; end if;
 if coalesce((select choice from public.consents where user_id=owner order by decided_at desc,id desc limit 1),'')<>'granted'
 then raise exception 'CONSENT_WITHDRAWN' using errcode='42501'; end if;
 select coalesce(timezone,'UTC') into zone from public.profiles where user_id=owner;
 if p_day is null or p_day<>nb.user_day_of(now(),coalesce(zone,'UTC'))
 then raise exception 'NOT_TODAY' using errcode='22023'; end if;
 budget:=public.consume_request_budget('meal-operation');
 if not (budget->>'allowed')::boolean then raise exception 'RATE_LIMITED' using errcode='54000'; end if;
 -- Same lock as apply_meal_operation: in-flight creates settle before clear.
 perform pg_advisory_xact_lock(hashtextextended(owner::text || ':meals',0));
 if not coalesce(p_clear_existing,false) and exists(select 1 from public.meals where user_id=owner and user_day=p_day and deleted_at is null)
 then raise exception 'FOOD_REQUIRES_CONFIRMATION' using errcode='22023'; end if;
 update public.meals set deleted_at=now() where user_id=owner and user_day=p_day and deleted_at is null;
 insert into public.fasted_days(user_id,user_day) values(owner,p_day) on conflict do nothing;
 return jsonb_build_object('user_day',p_day,'intake_state','FASTED','kcal_in',0);
end $$;
revoke all on function public.mark_day_fasted(date,boolean) from public,anon;
grant execute on function public.mark_day_fasted(date,boolean) to authenticated;

-- The confirmation explicitly closes food intake for this user day. Protect old clients,
-- delayed estimations, and direct table writes as well as the current outbox.
create function nb.guard_fasted_meal() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(new.user_id::text || ':meals',0));
 if new.deleted_at is null and exists(select 1 from public.fasted_days where user_id=new.user_id and user_day=new.user_day)
 then raise exception 'DAY_ALREADY_FASTED' using errcode='22023'; end if;
 return new;
end $$;
revoke all on function nb.guard_fasted_meal() from public,anon,authenticated;
create trigger guard_fasted_meal before insert or update on public.meals
 for each row execute function nb.guard_fasted_meal();

-- Preserve activity/revision fixes already applied to the fuel calculation.
do $$ declare definition text; patched text;
begin
 definition:=pg_get_functiondef('nb.compute_fuel(uuid,date)'::regprocedure);
 patched:=replace(definition, 'v_state := case',
   'v_state := case when exists(select 1 from public.fasted_days f where f.user_id=p_user and f.user_day=p_user_day) then ''FASTED''');
 if patched=definition then raise exception 'FASTING_COMPUTE_PATCH_MISSING'; end if;
 execute patched;
end $$;

-- A confirmed zero day has zero macros as well, including accounts without targets.
do $$ declare definition text; patched text;
begin
 definition:=pg_get_functiondef('nb.on_fuel_settled()'::regprocedure);
 patched:=replace(definition, '  return new;',
   '  if new.intake_state = ''FASTED'' then new.protein_in_g := 0; new.carb_in_g := 0; new.fat_in_g := 0; end if; return new;');
 if patched=definition then raise exception 'FASTING_MACROS_PATCH_MISSING'; end if;
 execute patched;
end $$;
