-- Remove the marked sample rows that were applied to the real account
-- 821819569@qq.com (see dev-samples.sql). Real band rows stay.
--
--   apply:   this file, via Management API / psql
--   markers: raw_samples.src = 'seed'
--            sleep_nights.raw ? 'seed'
--            meals.model_version = 'seed'
--            weigh_ins.health_uuid like 'seed-%'
--            body_composition.derived_fields @> '{seed}'

do $$
declare
  v_email text := coalesce(current_setting('nb.seed_email', true), '821819569@qq.com');
  v_user  uuid;
  v_tz    text;
  v_today date;
  n_samples int;
  n_sleep   int;
  n_meals   int;
  n_weigh   int;
  n_comp    int;
begin
  select id into v_user from auth.users where email = v_email;
  if v_user is null then raise exception 'no user %', v_email; end if;
  select timezone into v_tz from public.profiles where user_id = v_user;
  v_today := nb.user_day_of(now(), coalesce(v_tz, 'Asia/Shanghai'));

  delete from public.raw_samples      where user_id = v_user and src = 'seed';
  get diagnostics n_samples = row_count;
  delete from public.sleep_nights     where user_id = v_user and raw ? 'seed';
  get diagnostics n_sleep = row_count;
  delete from public.meals            where user_id = v_user and model_version = 'seed';
  get diagnostics n_meals = row_count;
  delete from public.weigh_ins        where user_id = v_user and health_uuid like 'seed-%';
  get diagnostics n_weigh = row_count;
  delete from public.body_composition where user_id = v_user and derived_fields @> '{seed}';
  get diagnostics n_comp = row_count;

  perform nb.recompute_range(v_user, v_today - 8, v_today, 'seed-cleanup');

  raise notice 'cleaned %: samples=% sleep=% meals=% weigh=% comp=%; recomputed % → %',
    v_email, n_samples, n_sleep, n_meals, n_weigh, n_comp, v_today - 8, v_today;
end $$;
