-- F3 §03 · RLS. Four actions written out separately — no shortcuts.
-- ⚠️ Edge Functions hold service_role, and service_role bypasses RLS: every statement
-- they run must carry its own `where user_id = $1`.
--
-- Every policy wraps auth.uid() in a sub-select so it is evaluated once per statement
-- rather than once per row, and every user_id column carries an index.

alter table public.profiles            enable row level security;
alter table public.devices             enable row level security;
alter table public.device_capabilities enable row level security;
alter table public.raw_samples         enable row level security;
alter table public.daily_results       enable row level security;
alter table public.daily_training      enable row level security;
alter table public.reserve_samples     enable row level security;
alter table public.reserve_daily       enable row level security;
alter table public.sleep_nights        enable row level security;
alter table public.body_composition    enable row level security;
alter table public.weigh_ins           enable row level security;
alter table public.meals               enable row level security;
alter table public.day_fuel            enable row level security;
alter table public.call_changes        enable row level security;
alter table public.screen_frames       enable row level security;
alter table public.analytics_events    enable row level security;
alter table public.sync_runs           enable row level security;
alter table public.ai_turns            enable row level security;
alter table public.banned_phrases      enable row level security;

-- ---------------------------------------------------------------- own row, full control

create policy profiles_select on public.profiles
  for select to authenticated using ((select auth.uid()) = user_id);
create policy profiles_insert on public.profiles
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy profiles_update on public.profiles
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy weigh_ins_select on public.weigh_ins
  for select to authenticated using ((select auth.uid()) = user_id);
create policy weigh_ins_insert on public.weigh_ins
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy weigh_ins_delete on public.weigh_ins
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------- meals: append + soft delete

create policy meals_select on public.meals
  for select to authenticated using ((select auth.uid()) = user_id);
create policy meals_insert on public.meals
  for insert to authenticated with check ((select auth.uid()) = user_id);
-- F3 §02.2 · the only mutation allowed is setting deleted_at. Everything else is refused,
-- enforced by the trigger below because Postgres has no column-level UPDATE policy.
create policy meals_soft_delete on public.meals
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function public.meals_only_soft_delete()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (new.id, new.user_id, new.user_day, new.slot, new.logged_at, new.text_input,
      new.kcal, new.protein_g, new.carb_g, new.fat_g, new.confidence,
      new.model_version, new.client_op_id)
     is distinct from
     (old.id, old.user_id, old.user_day, old.slot, old.logged_at, old.text_input,
      old.kcal, old.protein_g, old.carb_g, old.fat_g, old.confidence,
      old.model_version, old.client_op_id)
  then
    raise exception 'meals is append-only: an edit is a soft delete plus a new row';
  end if;
  return new;
end;
$$;

create trigger meals_append_only
  before update on public.meals
  for each row execute function public.meals_only_soft_delete();

-- ---------------------------------------------------------------- devices: never deleted

create policy devices_select on public.devices
  for select to authenticated using ((select auth.uid()) = user_id);
create policy devices_insert on public.devices
  for insert to authenticated with check ((select auth.uid()) = user_id);
-- Rebinding, writing unbound_at, updating battery and firmware all live here.
-- ⚠️ No delete policy: "Forget this HOOP" writes unbound_at, and 12's promise that
-- "your history stays" stands on that.
create policy devices_update on public.devices
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy device_caps_select on public.device_capabilities
  for select to authenticated using ((select auth.uid()) = user_id);
create policy device_caps_insert on public.device_capabilities
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy device_caps_update on public.device_capabilities
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------- results: read only

do $$
declare t text;
begin
  foreach t in array array['daily_results', 'daily_training', 'day_fuel',
                           'reserve_daily', 'call_changes']
  loop
    execute format(
      'create policy %I_select on public.%I for select to authenticated
         using ((select auth.uid()) = user_id)', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------- collected: insert only

do $$
declare t text;
begin
  foreach t in array array['raw_samples', 'reserve_samples', 'sleep_nights',
                           'body_composition', 'sync_runs']
  loop
    execute format(
      'create policy %I_select on public.%I for select to authenticated
         using ((select auth.uid()) = user_id)', t, t);
    execute format(
      'create policy %I_insert on public.%I for insert to authenticated
         with check ((select auth.uid()) = user_id)', t, t);
  end loop;
end $$;

-- sync_runs is the one collected table that gets closed out afterwards
create policy sync_runs_update on public.sync_runs
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------- append-only surfaces

create policy screen_frames_select on public.screen_frames
  for select to authenticated using ((select auth.uid()) = user_id);
create policy screen_frames_insert on public.screen_frames
  for insert to authenticated with check ((select auth.uid()) = user_id);

create policy ai_turns_select on public.ai_turns
  for select to authenticated using ((select auth.uid()) = user_id);

-- analytics has no select policy at all — writing is allowed, reading is not.
create policy analytics_insert on public.analytics_events
  for insert to authenticated with check ((select auth.uid()) = user_id);

-- the banned list is public read: the client-side validator needs it too
create policy banned_phrases_select on public.banned_phrases
  for select to authenticated using (true);

-- ---------------------------------------------------------------- retention

-- 90 days of frames, 180 days of events. Run as service_role, so RLS does not apply.
create or replace function public.prune_retention()
returns void
language sql
security definer
set search_path = ''
as $$
  with a as (delete from public.screen_frames where created_at < now() - interval '90 days')
  delete from public.analytics_events where server_ts < now() - interval '180 days';
$$;

revoke execute on function public.prune_retention() from public, anon, authenticated;
