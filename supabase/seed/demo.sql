-- Mock data so the whole flow is walkable without a band on the wrist.
-- One demo account, twelve weeks of raw points, weigh-ins and meals, then every user day
-- settled through the same nb.settle_day() the cron job calls.
--
-- Demo sign-in:  demo@nextbody.app  /  nextbody-demo

do $$
declare
  v_user uuid;
  d date;
  t timestamptz;
  i int;
  v_hr int;
  v_met numeric;
  v_seed numeric;
begin
  select id into v_user from auth.users where email = 'demo@nextbody.app';

  if v_user is null then
    v_user := extensions.gen_random_uuid();
    insert into auth.users
      (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
       raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values
      ('00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated',
       'demo@nextbody.app', extensions.crypt('nextbody-demo', extensions.gen_salt('bf')), now(),
       '{"provider":"email","providers":["email"]}'::jsonb,
       '{"name":"ALEX MERCER"}'::jsonb, now(), now());
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, created_at, updated_at)
    values (extensions.gen_random_uuid(), v_user, v_user::text,
            jsonb_build_object('sub', v_user::text, 'email', 'demo@nextbody.app'),
            'email', now(), now());
  end if;

  -- ⚠️ GoTrue reads these as NOT NULL. A hand-inserted row that leaves them null makes
  -- every sign-in fail with "Database error querying schema", which looks like an outage.
  update auth.users set
    confirmation_token         = coalesce(confirmation_token, ''),
    recovery_token             = coalesce(recovery_token, ''),
    email_change_token_new     = coalesce(email_change_token_new, ''),
    email_change               = coalesce(email_change, ''),
    email_change_token_current = coalesce(email_change_token_current, ''),
    phone_change               = coalesce(phone_change, ''),
    phone_change_token         = coalesce(phone_change_token, ''),
    reauthentication_token     = coalesce(reauthentication_token, '')
  where id = v_user;

  insert into public.profiles (user_id, timezone, sex, height_cm, birth_date, goal, field_sources)
  values (v_user, 'Asia/Shanghai', 'male', 182, date '1996-03-14', 'RECOMP',
          '{"height_cm":"health","birth_date":"health","sex":"health"}'::jsonb)
  on conflict (user_id) do update set
    timezone = excluded.timezone, height_cm = excluded.height_cm,
    birth_date = excluded.birth_date, goal = excluded.goal;

  insert into public.devices
    (user_id, ble_identifier, ble_identifier_kind, device_number, firmware_version,
     battery_percent, battery_is_percent, last_origin_sync_at)
  values (v_user, 'C4-2E-8F-1A-73-9D', 'uuid', 'HB-0042', '2.4.1', 82, true, now())
  on conflict do nothing;

  -- 84 user days of five-minute points
  for i in 0..83 loop
    d := (current_date - i);
    v_seed := (i * 7919 % 1000) / 1000.0;
    for t in select generate_series(
        (d + time '04:00') at time zone 'Asia/Shanghai',
        (d + 1 + time '04:00') at time zone 'Asia/Shanghai' - interval '5 minutes',
        interval '5 minutes')
    loop
      -- rest at night, a walk in the morning, a session in the evening
      v_hr := case
        when extract(hour from t at time zone 'Asia/Shanghai') between 0 and 6
          then 49 + (random() * 6)::int
        -- a 30-minute walk most mornings
        when extract(hour from t at time zone 'Asia/Shanghai') = 7
             and extract(minute from t at time zone 'Asia/Shanghai') < 35
          then 96 + (random() * 14)::int
        -- a 45-minute session on roughly two days in five
        when extract(hour from t at time zone 'Asia/Shanghai') = 18
             and extract(minute from t at time zone 'Asia/Shanghai') < 45
             and v_seed > 0.60 then 142 + (random() * 22)::int
        when extract(hour from t at time zone 'Asia/Shanghai') = 18
             and extract(minute from t at time zone 'Asia/Shanghai') < 45
             and v_seed > 0.35 then 118 + (random() * 16)::int
        else 60 + (random() * 10)::int
      end;
      v_met := greatest(1.0, v_hr / 62.0);
      insert into public.raw_samples
        (user_id, ts, sampled_tz, day_offset, calendar_day, heart, step, cal, met, stress,
         sleep_states, src)
      values (v_user, t, 'Asia/Shanghai', 0, d, v_hr,
              (random() * 45)::int, (random() * 6)::int, round(v_met, 2),
              20 + (random() * 30)::int,
              case when extract(hour from t at time zone 'Asia/Shanghai') between 0 and 6
                    or extract(hour from t at time zone 'Asia/Shanghai') = 23
                   then 2 else 0 end,
              'band')
      on conflict do nothing;
    end loop;

    -- sleep is an input only; it never reaches the screen
    insert into public.sleep_nights (user_id, user_day, total_minutes, deep_minutes, light_minutes, wake_count)
    values (v_user, d, 424 + (random() * 84)::int, 76 + (random() * 44)::int,
            220 + (random() * 60)::int, (random() * 3)::int)
    on conflict (user_id, user_day) do nothing;

    -- meals: most days logged, some days with a gap, one fasted day a fortnight
    if v_seed > 0.14 then
      insert into public.meals (user_id, user_day, slot, logged_at, text_input, kcal, protein_g, carb_g, fat_g, confidence, model_version, client_op_id)
      values
        (v_user, d, 'BREAKFAST', (d + time '07:20') at time zone 'Asia/Shanghai',
         'OATS · WHEY · BLUEBERRIES', 380 + (random() * 60)::int, 32, 44, 9, 'HIGH', 'seed', extensions.gen_random_uuid()),
        (v_user, d, 'LUNCH', (d + time '12:40') at time zone 'Asia/Shanghai',
         'CHICKEN · RICE · GREENS', 560 + (random() * 130)::int, 44, 62, 18, 'MEDIUM', 'seed', extensions.gen_random_uuid()),
        (v_user, d, 'DINNER', (d + time '19:40') at time zone 'Asia/Shanghai',
         'SALMON · POTATO · BROCCOLI', 600 + (random() * 160)::int, 46, 54, 24, 'MEDIUM', 'seed', extensions.gen_random_uuid())
      on conflict do nothing;
      if v_seed > 0.55 then
        insert into public.meals (user_id, user_day, slot, logged_at, text_input, kcal, protein_g, carb_g, fat_g, confidence, model_version, client_op_id)
        values (v_user, d, 'SNACK', (d + time '16:10') at time zone 'Asia/Shanghai',
                'GREEK YOGURT · ALMONDS', 240 + (random() * 60)::int, 22, 18, 11, 'HIGH', 'seed', extensions.gen_random_uuid())
        on conflict do nothing;
      end if;
    end if;

    -- a weigh-in most mornings, with a BIA reading every other day
    if v_seed > 0.22 then
      insert into public.weigh_ins (user_id, measured_at, sampled_tz, weight_kg, source, client_op_id)
      values (v_user, (d + time '06:40') at time zone 'Asia/Shanghai',
              'Asia/Shanghai', round((75.6 - i * 0.017 + (random() - 0.5) * 0.6)::numeric, 2),
              case when v_seed > 0.6 then 'health' else 'manual' end, extensions.gen_random_uuid());

      if v_seed > 0.4 then
        insert into public.body_composition
          (user_id, measured_at, user_day, measurement_source, input_weight_kg,
           body_fat_pct, fat_mass_kg, lean_body_mass_kg, bmr_kcal, derived_fields)
        values (v_user, (d + time '06:45') at time zone 'Asia/Shanghai', d, 'device_bia',
                round((75.6 - i * 0.017)::numeric, 2),
                round((14.6 + i * 0.012 + (random() - 0.5) * 0.4)::numeric, 2),
                round(((75.6 - i * 0.017) * (14.6 + i * 0.012) / 100)::numeric, 2),
                round(((75.6 - i * 0.017) * (1 - (14.6 + i * 0.012) / 100))::numeric, 2),
                1710, '{}');
      end if;
    end if;
  end loop;

  -- settle every one of those days through the same function the cron job calls
  perform nb.recompute_range(v_user, current_date - 83, current_date);

  raise notice 'seeded user %', v_user;
end $$;
