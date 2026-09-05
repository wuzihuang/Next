-- Overnight SpO2 is a first-class sample table: it must roll off with raw_samples,
-- leave with the account, and appear in the export. ADR-0002.

create or replace function public.prune_retention()
returns void
language sql
security definer
set search_path = ''
as $$
  with f as (delete from public.screen_frames where created_at < now() - interval '90 days'),
       e as (delete from public.analytics_events where server_ts < now() - interval '180 days')
  delete from public.oxygen_samples where ts < now() - interval '400 days';
  -- Raw health history is removed only by the verified archive finalizer.
$$;

create or replace function public.account_delete(confirm text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null then return jsonb_build_object('error', 'UNAUTHENTICATED'); end if;
  if confirm is distinct from 'DELETE' then return jsonb_build_object('error', 'E_SCHEMA'); end if;

  update public.profiles set deletion_requested_at = now() where user_id = v_user;
  delete from public.screen_frames where user_id = v_user;
  delete from public.ai_turns where user_id = v_user;
  delete from public.analytics_events where user_id = v_user;
  delete from public.call_changes where user_id = v_user;
  delete from public.meals where user_id = v_user;
  delete from public.weigh_ins where user_id = v_user;
  delete from public.body_composition where user_id = v_user;
  delete from public.oxygen_samples where user_id = v_user;
  delete from public.raw_samples where user_id = v_user;
  delete from public.reserve_samples where user_id = v_user;
  delete from public.sleep_nights where user_id = v_user;
  delete from public.night_hrv where user_id = v_user;
  delete from public.daily_results where user_id = v_user;
  delete from public.sync_runs where user_id = v_user;
  delete from public.device_capabilities where user_id = v_user;
  delete from public.devices where user_id = v_user;
  delete from public.profiles where user_id = v_user;
  delete from auth.users where id = v_user;
  return jsonb_build_object('deleted', true);
end;
$$;

create or replace function public.export_all()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.user_id = (select auth.uid())),
    'days', (select coalesce(jsonb_agg(to_jsonb(d) order by d.user_day), '[]'::jsonb)
             from public.daily_results d where d.user_id = (select auth.uid())),
    'weigh_ins', (select coalesce(jsonb_agg(to_jsonb(w) order by w.measured_at), '[]'::jsonb)
                  from public.weigh_ins w where w.user_id = (select auth.uid())),
    'composition', (select coalesce(jsonb_agg(to_jsonb(b) order by b.measured_at), '[]'::jsonb)
                    from public.body_composition b where b.user_id = (select auth.uid())),
    'night_hrv', (select coalesce(jsonb_agg(to_jsonb(h) order by h.user_day), '[]'::jsonb)
                  from public.night_hrv h where h.user_id = (select auth.uid())),
    'oxygen_samples', (select coalesce(jsonb_agg(to_jsonb(o) order by o.ts), '[]'::jsonb)
                       from public.oxygen_samples o where o.user_id = (select auth.uid())),
    'meals', (select coalesce(jsonb_agg(to_jsonb(m) order by m.logged_at), '[]'::jsonb)
              from public.meals m where m.user_id = (select auth.uid()) and m.deleted_at is null));
$$;
