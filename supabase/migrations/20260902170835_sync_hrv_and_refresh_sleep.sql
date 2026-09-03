-- HRV is not a five-minute OriginData scalar. The SDK gives minute RR intervals in a
-- separate database; the client derives minute RMSSD, collapses to 15-minute medians, and
-- uploads one nightly median. Vendor hrvValue is deliberately not stored as RMSSD.
create table public.night_hrv (
  user_id       uuid not null references auth.users (id) on delete cascade,
  user_day      date not null,
  rmssd_ms      numeric(6, 2) not null check (rmssd_ms between 1 and 300),
  bucket_count  smallint not null check (bucket_count > 0),
  rr_count      integer not null check (rr_count > 1),
  sampled_tz    text not null,
  source        text not null check (source in ('band_rr')),
  collected_at  timestamptz not null default now(),
  primary key (user_id, user_day)
);

alter table public.night_hrv enable row level security;
create policy night_hrv_select on public.night_hrv
  for select to authenticated using ((select auth.uid()) = user_id);
create policy night_hrv_insert on public.night_hrv
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy night_hrv_update on public.night_hrv
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- A night can still be in progress at 05:00. Re-reading it must refresh the same row rather
-- than being ignored forever by the primary key.
create policy sleep_nights_update on public.sleep_nights
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update on public.night_hrv to authenticated;
grant update on public.sleep_nights to authenticated;

-- Keep account erasure/export complete after adding the HRV domain. The Edge functions use
-- the same list, while these RPCs remain the database-owned fallback path.
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
    'meals', (select coalesce(jsonb_agg(to_jsonb(m) order by m.logged_at), '[]'::jsonb)
              from public.meals m where m.user_id = (select auth.uid()) and m.deleted_at is null));
$$;

create or replace function nb.charge_multiplier(p_user uuid, p_user_day date, p_tz text)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  v_hrv      numeric;
  v_hrv_mean numeric;
  v_hrv_sd   numeric;
  v_hrv_n    integer;
  v_rhr      numeric;
  v_rhr_mean numeric;
  v_rhr_sd   numeric;
  v_rhr_n    integer;
  v_m_hrv    numeric := 1.00;
  v_m_rhr    numeric := 1.00;
begin
  select h.rmssd_ms into v_hrv
  from public.night_hrv h where h.user_id = p_user and h.user_day = p_user_day;
  select count(*), avg(h.rmssd_ms), stddev_samp(h.rmssd_ms)
    into v_hrv_n, v_hrv_mean, v_hrv_sd
  from public.night_hrv h
  where h.user_id = p_user
    and h.user_day between p_user_day - 14 and p_user_day - 1;
  if v_hrv is not null and coalesce(v_hrv_n, 0) >= 5 and coalesce(v_hrv_sd, 0) >= 0.5 then
    v_m_hrv := least(1.25, greatest(0.75,
      1.00 + 0.25 * ((v_hrv - v_hrv_mean) / v_hrv_sd)));
  end if;

  v_rhr := nb.night_rhr(p_user, p_user_day, p_tz);
  select count(*), avg(r), stddev_samp(r) into v_rhr_n, v_rhr_mean, v_rhr_sd
  from (
    select nb.night_rhr(p_user, d::date, p_tz) as r
    from generate_series(p_user_day - 14, p_user_day - 1, interval '1 day') d
  ) s where r is not null;
  if v_rhr is not null and coalesce(v_rhr_n, 0) >= 5 and coalesce(v_rhr_sd, 0) >= 0.5 then
    v_m_rhr := least(1.25, greatest(0.75,
      1.00 + 0.25 * ((v_rhr_mean - v_rhr) / v_rhr_sd)));
  end if;

  return least(1.30, greatest(0.65, v_m_hrv * v_m_rhr));
end;
$$;

create or replace function nb.night_inputs(p_user uuid, p_user_day date)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz       text;
  v_rhr      numeric;
  v_rhr_base numeric;
  v_rhr_n    integer;
  v_hrv      numeric;
  v_hrv_base numeric;
  v_hrv_n    integer;
begin
  select timezone into v_tz from public.profiles where user_id = p_user;
  if v_tz is null then return '{}'::jsonb; end if;

  v_rhr := nb.night_rhr(p_user, p_user_day, v_tz);
  select count(*), avg(r) into v_rhr_n, v_rhr_base
  from (
    select nb.night_rhr(p_user, d::date, v_tz) as r
    from generate_series(p_user_day - 14, p_user_day - 1, interval '1 day') d
  ) s where r is not null;

  select h.rmssd_ms into v_hrv
  from public.night_hrv h where h.user_id = p_user and h.user_day = p_user_day;
  select count(*), avg(h.rmssd_ms) into v_hrv_n, v_hrv_base
  from public.night_hrv h
  where h.user_id = p_user
    and h.user_day between p_user_day - 14 and p_user_day - 1;

  return jsonb_build_object(
    'rhr',        case when v_rhr is null then null else round(v_rhr) end,
    'rhr_base',   case when coalesce(v_rhr_n, 0) = 0 then null else round(v_rhr_base) end,
    'rhr_nights', coalesce(v_rhr_n, 0),
    'hrv',        case when v_hrv is null then null else round(v_hrv) end,
    'hrv_base',   case when coalesce(v_hrv_n, 0) = 0 then null else round(v_hrv_base) end,
    'hrv_nights', coalesce(v_hrv_n, 0),
    'multiplier', round(nb.charge_multiplier(p_user, p_user_day, v_tz), 2));
end;
$$;
