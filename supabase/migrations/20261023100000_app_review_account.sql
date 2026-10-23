-- App Review account · demo@nextbody.ai, signed in on a real phone with the six digits 202610
-- (the app sends them as the password; see ReviewAccount in app/NextBody/Services/Supabase.swift).
-- Everything in it is synthetic, in the shape supabase/seed/demo.sql gives the simulator
-- account, written against the current schema. Every night the account is deleted and rebuilt
-- under the same id, so its days stay current and whatever a reviewer logged is gone by morning.
--
-- ⚠️ Deleting the auth user is the wipe: every public table's user_id references auth.users
-- on delete cascade. nb tables that carry a user_id without that reference are cleared by
-- hand below. A reviewer signed in across the 04:15 Los Angeles rebuild is signed out once.

create or replace function nb.reset_review_account()
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user constant uuid := '9e6499b1-faa3-4bee-84b1-717875526c47';
  v_tz constant text := 'America/Los_Angeles';
  v_today date := (timezone('America/Los_Angeles', now()))::date;
  v_table record;
  d date;
  t timestamptz;
  i int;
  v_hr int;
  v_met numeric;
  v_seed numeric;
  v_scale numeric;
  v_hour int;
  v_minute int;
  v_walk boolean;
  v_train boolean;
  v_asleep boolean;
  v_deep boolean;
  v_moving boolean;
  v_bed timestamptz;
  v_wake timestamptz;
  v_bed_next timestamptz;
  v_step int;
  v_total int;
  v_deep_min int;
  v_rem_min int;
  v_awake_min int;
  v_light_min int;
  v_weight numeric;
  v_fat numeric;
begin
  delete from auth.users where id = v_user or email = 'demo@nextbody.ai';
  for v_table in
    select c.table_schema, c.table_name
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
    where c.column_name = 'user_id' and c.table_schema = 'nb' and tb.table_type = 'BASE TABLE'
  loop
    execute format('delete from %I.%I where user_id = $1', v_table.table_schema, v_table.table_name)
      using v_user;
  end loop;

  insert into auth.users
    (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
     raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
     confirmation_token, recovery_token, email_change_token_new, email_change,
     email_change_token_current, phone_change, phone_change_token, reauthentication_token)
  values
    ('00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated',
     'demo@nextbody.ai', extensions.crypt('202610', extensions.gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     '{"name":"ALEX"}'::jsonb, now() - interval '182 days', now(),
     -- ⚠️ GoTrue reads these as NOT NULL; leaving them null fails every sign-in with
     -- "Database error querying schema".
     '', '', '', '', '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, created_at, updated_at)
  values (extensions.gen_random_uuid(), v_user, v_user::text,
          jsonb_build_object('sub', v_user::text, 'email', 'demo@nextbody.ai'),
          'email', now(), now());

  insert into public.profiles (user_id, timezone, sex, height_cm, birth_date, goal, display_name, field_sources)
  values (v_user, v_tz, 'male', 182, date '1994-03-14', 'RECOMP', 'ALEX',
          '{"height_cm":"health","birth_date":"health","sex":"health"}'::jsonb)
  on conflict (user_id) do update set
    timezone = excluded.timezone, sex = excluded.sex, height_cm = excluded.height_cm,
    birth_date = excluded.birth_date, goal = excluded.goal, display_name = excluded.display_name;

  insert into public.devices
    (user_id, ble_identifier, ble_identifier_kind, device_number, firmware_version,
     battery_percent, battery_is_percent, bound_at, last_origin_sync_at)
  values (v_user, 'C4-2E-8F-1A-73-9D', 'uuid', 'HB-0042', '2.4.1', 82, true,
          now() - interval '182 days', now());

  -- Twenty-six weeks of 5-minute ticks, cut on the profile's 04:00 day, never past now.
  for i in 0..181 loop
    d := v_today - i;
    v_seed := (hashtext(d::text) & 2147483647) / 2147483647.0;
    v_scale := 0.80 + ((hashtext(d::text || 'kcal') & 2147483647) / 2147483647.0) * 0.55;
    -- Bed 23:00–23:40 the evening before, wake 06:20–07:00: a regular sleeper, not a metronome.
    v_bed := ((d - 1) + time '23:00') at time zone v_tz
             + make_interval(mins => ((hashtext(d::text || 'bed') & 2147483647) % 40));
    v_wake := (d + time '06:20') at time zone v_tz
              + make_interval(mins => ((hashtext(d::text || 'wake') & 2147483647) % 40));
    v_bed_next := (d + time '23:00') at time zone v_tz
                  + make_interval(mins => ((hashtext((d + 1)::text || 'bed') & 2147483647) % 40));

    for t in select generate_series(
        (d + time '04:00') at time zone v_tz,
        least((d + 1 + time '04:00') at time zone v_tz - interval '5 minutes',
              date_trunc('hour', now()) + interval '5 minutes' * floor(extract(minute from now()) / 5)),
        interval '5 minutes')
    loop
      v_hour := extract(hour from t at time zone v_tz)::int;
      v_minute := extract(minute from t at time zone v_tz)::int;
      v_asleep := t < v_wake or t >= v_bed_next;
      v_deep := v_asleep and t < v_wake and (t - v_bed) between interval '50 minutes' and interval '150 minutes';
      v_walk := not v_asleep and v_hour = 7 and v_minute between 20 and 55;
      v_train := v_hour = 18 and v_minute < 45 and v_seed > 0.30;

      -- Seated ticks straddle RHR+5 on purpose so part of the day counts as rest and the
      -- body battery stays in a human range (see the notes in supabase/seed/demo.sql).
      v_hr := case
        when v_asleep then 47 + (random() * 6)::int
        when v_walk then 96 + (random() * 14)::int
        when v_train and v_seed > 0.75 then 148 + (random() * 16)::int
        when v_train then 126 + (random() * 16)::int
        when random() < 0.12 then 76 + (random() * 16)::int
        else round(50 + random() * 9.5)::int
      end;
      v_moving := v_walk or v_train or v_hr > 70;
      v_met := case when v_asleep then 0.95 when v_moving then greatest(1.0, v_hr / 62.0) else 1.0 end;
      v_step := case when v_asleep then 0
                     when v_walk then 520 + (random() * 90)::int
                     when v_train then 40 + (random() * 60)::int
                     when v_moving then 60 + (random() * 140)::int
                     else 0 end;

      insert into public.raw_samples
        (user_id, ts, sampled_tz, heart, step, cal, dis, met, temp, stress, sleep_states, hrv, src)
      values (v_user, t, v_tz, v_hr, v_step,
              case when v_asleep then 4 else 3 + (random() * 9)::int end,
              round(v_step * 0.74)::int,
              round(v_met, 2),
              round((case when v_asleep then 35.1 else 33.4 end + (random() - 0.5) * 0.6)::numeric, 1),
              case when v_asleep then 18 + (random() * 10)::int
                   when v_train then 55 + (random() * 25)::int
                   when v_hour between 14 and 15 then 52 + (random() * 20)::int
                   when v_moving then 34 + (random() * 16)::int
                   else 26 + (random() * 12)::int end,
              -- 1 deep · 2 light · 3 awake in bed · 0 not asleep
              case when v_deep then 1
                   when v_asleep and random() < 0.05 then 3
                   when v_asleep then 2
                   else 0 end,
              case when v_asleep then 46 + (random() * 18)::int end,
              'band')
      on conflict do nothing;
    end loop;

    -- The band is newer than the account: nights exist for the last fourteen days only,
    -- which also bounds the body-battery chain (see supabase/seed/demo.sql).
    if i <= 13 then
      v_total := (extract(epoch from (v_wake - v_bed)) / 60)::int;
      v_awake_min := 8 + (random() * 14)::int;
      v_deep_min := 85 + (random() * 25)::int;
      v_rem_min := 90 + (random() * 25)::int;
      v_light_min := v_total - v_awake_min - v_deep_min - v_rem_min;
      insert into public.sleep_nights
        (user_id, user_day, total_minutes, deep_minutes, light_minutes, wake_count,
         sleep_start, wake_at, sleep_line, raw)
      values (v_user, d, v_total - v_awake_min, v_deep_min, v_light_min, 1 + (random() * 2)::int,
              v_bed, v_wake,
              -- 0 deep · 1 light · 2 REM · 3 awake, in the order the night ran
              format('1:%s,0:%s,1:%s,2:%s,0:%s,1:%s,3:%s,2:%s,1:%s',
                     20, v_deep_min - 30, 45, v_rem_min / 2, 30,
                     v_light_min - 65 - 25, v_awake_min, v_rem_min - v_rem_min / 2, 25),
              jsonb_build_object('hrv', (
                select jsonb_agg(jsonb_build_object(
                  'ts', to_char((v_bed + m * interval '1 minute') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                  'rmssd_ms', 44 + (m % 11) + round(v_seed * 8)::int))
                from generate_series(0, v_total - 1, 5) m)))
      on conflict (user_id, user_day) do nothing;
    end if;

    -- Meals on most days; today only the meals that have already happened.
    if v_seed > 0.14 or i = 0 then
      insert into public.meals (user_id, user_day, slot, logged_at, text_input, kcal, protein_g, carb_g, fat_g, confidence, model_version, client_op_id)
      select v_user, d, m.slot, m.at, m.text, m.kcal, m.p, m.c, m.f, m.conf, 'seed', extensions.gen_random_uuid()
      from (values
        ('BREAKFAST', (d + time '07:20') at time zone v_tz, 'Oats, whey and blueberries',
         round((300 + random() * 50) * v_scale)::int, 34, 34, 8, 'HIGH'),
        ('LUNCH', (d + time '12:40') at time zone v_tz, 'Chicken, rice and greens',
         round((450 + random() * 90) * v_scale)::int, 50, 46, 14, 'MEDIUM'),
        ('DINNER', (d + time '19:40') at time zone v_tz, 'Salmon, potato and broccoli',
         round((480 + random() * 120) * v_scale)::int, 52, 42, 18, 'MEDIUM')
      ) as m(slot, at, text, kcal, p, c, f, conf)
      where m.at <= now()
      on conflict do nothing;
      if v_seed > 0.55 then
        insert into public.meals (user_id, user_day, slot, logged_at, text_input, kcal, protein_g, carb_g, fat_g, confidence, model_version, client_op_id)
        select v_user, d, 'SNACK', (d + time '16:10') at time zone v_tz, 'Greek yogurt and almonds',
               round((180 + random() * 50) * v_scale)::int, 24, 14, 8, 'HIGH', 'seed', extensions.gen_random_uuid()
        where (d + time '16:10') at time zone v_tz <= now()
        on conflict do nothing;
      end if;
    end if;

    -- A weigh-in most mornings and a band body scan on some of them.
    if v_seed > 0.22 and (d + time '06:40') at time zone v_tz <= now() then
      v_weight := round((75.6 + i * 0.017 + (random() - 0.5) * 0.6)::numeric, 2);
      v_fat := round((14.8 + i * 0.038 + (random() - 0.5) * 0.25)::numeric, 1);
      insert into public.weigh_ins (user_id, measured_at, sampled_tz, weight_kg, source, client_op_id)
      values (v_user, (d + time '06:40') at time zone v_tz, v_tz, v_weight,
              case when v_seed > 0.6 then 'health' else 'manual' end, extensions.gen_random_uuid());
      if v_seed > 0.4 then
        insert into public.body_composition
          (user_id, measured_at, user_day, measurement_source, input_weight_kg,
           body_fat_pct, fat_mass_kg, lean_body_mass_kg, muscle_mass_kg, body_water_pct,
           bone_mass_kg, protein_pct, bmr_kcal, derived_fields)
        values (v_user, (d + time '06:45') at time zone v_tz, d, 'device_bia', v_weight,
                v_fat, round(v_weight * v_fat / 100, 1), round(v_weight * (1 - v_fat / 100), 1),
                round(v_weight * (1 - v_fat / 100) * 0.73, 1), round(64.5 - v_fat * 0.6, 1),
                2.7, round(19.5 - v_fat * 0.1, 1), 1710, '{}');
      end if;
    end if;
  end loop;

  -- Five weeks settled: the month views and every baseline. All 84 took 9½ minutes on
  -- production, too long to spend every night on an account nobody owns.
  perform nb.recompute_range(v_user, v_today - 34, v_today, 'review-reset');
  return v_user;
end $$;

revoke execute on function nb.reset_review_account() from public, anon, authenticated;

-- 04:15 in Los Angeles (11:15 UTC; 12:15 in winter), after the night has closed.
-- ⚠️ The rebuild settles 35 days and runs past the project's 2-minute statement_timeout; a SET
-- on the function does not lift a timer that is already running, a SET ahead of it does.
select cron.schedule('nb-review-reset', '15 11 * * *',
  $$set statement_timeout = '15min'; select nb.reset_review_account()$$);
