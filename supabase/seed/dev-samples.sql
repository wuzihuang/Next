-- Eight days of marked sample data for ONE real account, so the chart tools have something
-- to draw on a phone whose band has not synced yet. Every row carries a marker and the
-- block at the bottom removes them all:
--   raw_samples.src = 'seed' · sleep_nights.raw ? 'seed' · meals.model_version = 'seed'
--   weigh_ins.health_uuid like 'seed-%' · body_composition.derived_fields @> '{seed}'
--
-- ⚠️ Real band rows (src = 'band') and seed rows for the same tick are BOTH counted by the
-- settle functions. Run the cleanup before trusting a day the band has actually synced.
--
--   apply:   psql "$DB" -v email="'821819569@qq.com'" -f supabase/seed/dev-samples.sql
--   cleanup: supabase/seed/cleanup-dev-samples.sql
--            (also the commented block at the end of this file)

do $$
declare
  v_email text := coalesce(current_setting('nb.seed_email', true), '821819569@qq.com');
  v_user  uuid;
  v_tz    text;
  v_today date;
  d       date;
  t       timestamptz;
  i       int;
  v_hr    int;
  v_met   numeric;
  v_seed  numeric;
  v_hour  int;
  v_min   int;
  v_walk  bool;
  v_train bool;
  v_asleep bool;
  v_moving bool;
  v_scale numeric;
  v_wkg   numeric;
  v_fat   numeric;
begin
  select id into v_user from auth.users where email = v_email;
  if v_user is null then raise exception 'no user %', v_email; end if;
  select timezone into v_tz from public.profiles where user_id = v_user;
  v_tz := coalesce(v_tz, 'Asia/Shanghai');
  v_today := nb.user_day_of(now(), v_tz);

  for i in 0..7 loop
    d := v_today - i;
    v_seed  := (hashtext(d::text) & 2147483647) / 2147483647.0;
    v_scale := 0.80 + ((hashtext(d::text || 'kcal') & 2147483647) / 2147483647.0) * 0.55;

    -- five-minute ticks from 04:00, stopping at the last tick that has actually happened
    for t in select generate_series(
        (d + time '04:00') at time zone v_tz,
        least((d + 1 + time '04:00') at time zone v_tz - interval '5 minutes',
              date_trunc('hour', now()) + interval '5 minutes' * floor(extract(minute from now()) / 5)),
        interval '5 minutes')
    loop
      v_hour := extract(hour from t at time zone v_tz)::int;
      v_min  := extract(minute from t at time zone v_tz)::int;
      v_walk := v_hour = 7 and v_min < 35;
      v_train := v_hour = 18 and v_min < 45 and v_seed > 0.30;
      v_asleep := v_hour * 60 + v_min < 390;
      -- a 97 kg, 30-year-old male: RHR ~58, HR max ~190
      v_hr := case
        when v_asleep then 54 + (random() * 6)::int
        when v_walk then 98 + (random() * 14)::int
        when v_train and v_seed > 0.75 then 150 + (random() * 16)::int
        when v_train then 128 + (random() * 16)::int
        when random() < 0.12 then 80 + (random() * 16)::int
        else round(58 + random() * 9.5)::int
      end;
      v_moving := v_walk or v_train or v_hr > 78;
      v_met := case when v_asleep then 0.95 when v_moving then greatest(1.0, v_hr / 70.0) else 1.0 end;

      if exists (select 1 from public.raw_samples r where r.user_id = v_user and r.ts = t and r.src <> 'seed') then
        continue;
      end if;
      insert into public.raw_samples (user_id, ts, sampled_tz, heart, step, cal, dis, met, temp, stress, sleep_states, src)
      values (v_user, t, v_tz, v_hr,
              case when v_asleep then 0
                   when v_walk then 520 + (random() * 90)::int
                   when v_train then 40 + (random() * 60)::int
                   when v_moving then 60 + (random() * 140)::int
                   else 0 end,
              case when v_asleep then 5 else 4 + (random() * 10)::int end,
              case when v_walk then 400 + (random() * 60)::int when v_moving then 40 + (random() * 90)::int else 0 end,
              round(v_met, 2),
              round((36.3 + random() * 0.5)::numeric, 2),
              case when v_asleep then 18 + (random() * 10)::int
                   when v_train then 55 + (random() * 25)::int
                   when v_hour between 14 and 15 then 52 + (random() * 20)::int
                   when v_moving then 34 + (random() * 16)::int
                   else 26 + (random() * 12)::int end,
              case when v_hour between 1 and 2 then 1 when v_asleep and random() < 0.06 then 3 when v_asleep then 2 else 0 end,
              'seed')
      on conflict do nothing;
    end loop;

    insert into public.sleep_nights (user_id, user_day, total_minutes, deep_minutes, light_minutes, wake_count, raw)
    values (v_user, d, 390, 120, 250, (random() * 3)::int, '{"seed": true}'::jsonb)
    on conflict (user_id, user_day) do nothing;

    -- meals: most days logged; today only the meals that have already happened
    if v_seed > 0.14 or i = 0 then
      insert into public.meals (user_id, user_day, slot, logged_at, text_input, kcal, protein_g, carb_g, fat_g, confidence, model_version, client_op_id)
      select v_user, d, m.slot, m.at, m.text, m.kcal, m.p, m.c, m.f, m.conf, 'seed', extensions.gen_random_uuid()
      from (values
        ('BREAKFAST', (d + time '07:20') at time zone v_tz, '燕麦 · 鸡蛋 · 牛奶',   round((360 + random() * 50) * v_scale)::int, 28, 42, 12, 'HIGH'),
        ('LUNCH',     (d + time '12:40') at time zone v_tz, '鸡胸 · 米饭 · 西兰花', round((520 + random() * 90) * v_scale)::int, 48, 58, 14, 'MEDIUM'),
        ('DINNER',    (d + time '19:40') at time zone v_tz, '三文鱼 · 土豆 · 青菜', round((560 + random() * 120) * v_scale)::int, 46, 44, 20, 'MEDIUM')
      ) as m(slot, at, text, kcal, p, c, f, conf)
      where m.at <= now()
      on conflict do nothing;
      if v_seed > 0.55 then
        insert into public.meals (user_id, user_day, slot, logged_at, text_input, kcal, protein_g, carb_g, fat_g, confidence, model_version, client_op_id)
        select v_user, d, 'SNACK', (d + time '16:10') at time zone v_tz, '希腊酸奶 · 坚果',
               round((200 + random() * 50) * v_scale)::int, 20, 16, 9, 'HIGH', 'seed', extensions.gen_random_uuid()
        where (d + time '16:10') at time zone v_tz <= now()
        on conflict do nothing;
      end if;
    end if;

    -- a weigh-in most mornings, a BIA reading every other day, both trending the CUT way
    v_wkg := round((97.0 - (7 - i) * 0.06 + (random() - 0.5) * 0.4)::numeric, 2);
    v_fat := round((32.4 + i * 0.05 + (random() - 0.5) * 0.2)::numeric, 2);
    if v_seed > 0.22 and (d + time '06:40') at time zone v_tz <= now() then
      insert into public.weigh_ins (user_id, measured_at, sampled_tz, weight_kg, source, health_uuid, client_op_id)
      values (v_user, (d + time '06:40') at time zone v_tz, v_tz, v_wkg, 'manual', 'seed-' || d::text, extensions.gen_random_uuid())
      on conflict do nothing;
      if v_seed > 0.4 then
        insert into public.body_composition
          (user_id, measured_at, user_day, measurement_source, input_weight_kg, body_fat_pct, fat_mass_kg, lean_body_mass_kg, bmr_kcal, derived_fields)
        values (v_user, (d + time '06:45') at time zone v_tz, d, 'manual', v_wkg, v_fat,
                round((v_wkg * v_fat / 100)::numeric, 2), round((v_wkg * (1 - v_fat / 100))::numeric, 2), 2208, '{seed}');
      end if;
    end if;
  end loop;

  perform nb.recompute_range(v_user, v_today - 7, v_today, 'seed');
  raise notice 'seeded % (%) for % → %', v_email, v_user, v_today - 7, v_today;
end $$;

-- ---------------------------------------------------------------- cleanup
-- do $$
-- declare v_user uuid; v_tz text; v_today date;
-- begin
--   select id into v_user from auth.users where email = '821819569@qq.com';
--   select timezone into v_tz from public.profiles where user_id = v_user;
--   v_today := nb.user_day_of(now(), coalesce(v_tz, 'Asia/Shanghai'));
--   delete from public.raw_samples      where user_id = v_user and src = 'seed';
--   delete from public.sleep_nights     where user_id = v_user and raw ? 'seed';
--   delete from public.meals            where user_id = v_user and model_version = 'seed';
--   delete from public.weigh_ins        where user_id = v_user and health_uuid like 'seed-%';
--   delete from public.body_composition where user_id = v_user and derived_fields @> '{seed}';
--   perform nb.recompute_range(v_user, v_today - 8, v_today, 'seed-cleanup');
-- end $$;
