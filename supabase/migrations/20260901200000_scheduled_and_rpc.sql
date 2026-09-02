-- What can be deployed without the CLI.
--
-- Eight of F4's endpoints are Edge Functions and four of those exist to reach the model;
-- those genuinely need `supabase functions deploy`. But the settle job, the retention sweep
-- and the account deletion are database work that only ran because I ran them by hand, and
-- a nightly job nobody has ever seen run is not a nightly job. All three are scheduled or
-- callable now, using the credentials that are actually in hand.

create extension if not exists pg_cron with schema extensions;

-- ---------------------------------------------------------------- settle

-- F3 · the day settles once, for everyone, after the 04:00 cut has passed everywhere it
-- could matter. ⚠️ Two days back, not one: OriginData arrives late as a matter of course —
-- the band is an offline device — and a settle that only ever looks at yesterday can never
-- incorporate a page that showed up this morning.
create or replace function nb.settle_all(p_days integer default 2)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare u record; n integer := 0;
begin
  for u in select user_id, timezone from public.profiles loop
    -- Each user's own calendar. A single UTC date would settle the wrong day for
    -- everyone east or west of Greenwich.
    perform nb.recompute_range(
      u.user_id,
      (timezone(u.timezone, now()))::date - p_days,
      (timezone(u.timezone, now()))::date,
      'cron');
    n := n + 1;
  end loop;
  return n;
end;
$$;

revoke execute on function nb.settle_all(integer) from public, anon, authenticated;

-- Hourly, because "after 04:00" is a different instant in every timezone and the settle is
-- idempotent — it recomputes from the same ticks and writes the same row.
select cron.unschedule('nb-settle') where exists (
  select 1 from cron.job where jobname = 'nb-settle');
select cron.schedule('nb-settle', '7 * * * *', $job$ select nb.settle_all(2) $job$);

-- ---------------------------------------------------------------- retention

-- 1DLA · daily_results / weigh_ins / body_composition / meals / call_changes are never
-- deleted; raw_samples rolls at 400 days, screen_frames at 90, analytics_events at 180.
-- ⚠️ raw_samples was named in that rule and missing from the function.
create or replace function public.prune_retention()
returns void
language sql
security definer
set search_path = ''
as $$
  with f as (delete from public.screen_frames where created_at < now() - interval '90 days'),
       e as (delete from public.analytics_events where server_ts < now() - interval '180 days')
  delete from public.raw_samples where ts < now() - interval '400 days';
$$;

revoke execute on function public.prune_retention() from public, anon, authenticated;

select cron.unschedule('nb-prune') where exists (
  select 1 from cron.job where jobname = 'nb-prune');
select cron.schedule('nb-prune', '23 4 * * *', $job$ select public.prune_retention() $job$);

-- ---------------------------------------------------------------- account deletion

-- F4 keeps account.delete as an endpoint because the model-facing surface is defined there,
-- but the work itself is entirely database work, and 1DPG is explicit that a failure here is
-- a legal event rather than a toast. Until the function is deployed the button had nothing
-- to call — so this is the same deletion, reachable over PostgREST as an RPC.
--
-- ⚠️ It deletes only the caller's own rows: auth.uid() is the subject, never an argument.
-- An account id passed in by a client is an account id a client can change.
create or replace function public.account_delete(confirm text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := (select auth.uid());
begin
  if v_user is null then return jsonb_build_object('error', 'UNAUTHENTICATED'); end if;
  -- 11 · the second confirmation is a literal, so a mis-routed call cannot delete anything.
  if confirm is distinct from 'DELETE' then return jsonb_build_object('error', 'E_SCHEMA'); end if;

  update public.profiles set deletion_requested_at = now() where user_id = v_user;

  delete from public.screen_frames     where user_id = v_user;
  delete from public.ai_turns          where user_id = v_user;
  delete from public.analytics_events  where user_id = v_user;
  delete from public.call_changes      where user_id = v_user;
  delete from public.meals             where user_id = v_user;
  delete from public.weigh_ins         where user_id = v_user;
  delete from public.body_composition  where user_id = v_user;
  delete from public.raw_samples       where user_id = v_user;
  delete from public.reserve_samples   where user_id = v_user;
  delete from public.sleep_nights      where user_id = v_user;
  delete from public.daily_results     where user_id = v_user;   -- cascades to the three detail tables
  delete from public.sync_runs         where user_id = v_user;
  delete from public.device_capabilities where user_id = v_user;
  delete from public.devices           where user_id = v_user;
  delete from public.profiles          where user_id = v_user;
  -- ⚠️ auth.users last, and by cascade: deleting it first would strip auth.uid() out from
  -- under the statements above and leave the rows behind under a user that no longer exists.
  delete from auth.users               where id = v_user;

  return jsonb_build_object('deleted', true);
end;
$$;

revoke execute on function public.account_delete(text) from public, anon;
grant execute on function public.account_delete(text) to authenticated;

-- ---------------------------------------------------------------- export

-- 11 · EXPORT MY DATA · ALL TIME. 1ACT leaves the format and the audience undecided, so this
-- is the conservative reading: everything the account owns, as JSON, to the account itself.
-- No sharing, no third party, no new compliance surface.
create or replace function public.export_all()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'exported_at', now(),
    'profile',     (select to_jsonb(p) from public.profiles p where p.user_id = (select auth.uid())),
    'days',        (select coalesce(jsonb_agg(to_jsonb(d) order by d.user_day), '[]'::jsonb)
                    from public.daily_results d where d.user_id = (select auth.uid())),
    'weigh_ins',   (select coalesce(jsonb_agg(to_jsonb(w) order by w.measured_at), '[]'::jsonb)
                    from public.weigh_ins w where w.user_id = (select auth.uid())),
    'composition', (select coalesce(jsonb_agg(to_jsonb(b) order by b.measured_at), '[]'::jsonb)
                    from public.body_composition b where b.user_id = (select auth.uid())),
    'meals',       (select coalesce(jsonb_agg(to_jsonb(m) order by m.logged_at), '[]'::jsonb)
                    from public.meals m where m.user_id = (select auth.uid()) and m.deleted_at is null));
$$;

revoke execute on function public.export_all() from public, anon;
grant execute on function public.export_all() to authenticated;
