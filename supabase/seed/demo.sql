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
  v_hour integer;
  v_minute integer;
  v_walk boolean;
  v_train boolean;
  v_asleep boolean;
  v_moving boolean;
  v_scale numeric;
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
  values (v_user, 'America/Los_Angeles', 'male', 182, date '1996-03-14', 'RECOMP',
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
  -- ⚠️ The loop walks the profile's calendar, not the server's. current_date is UTC, and
  -- seeding against it puts the whole demo a day out for anyone west of Greenwich: the
  -- app cuts its days in the device's zone and would find today empty.
  for i in 0..83 loop
    d := (timezone('America/Los_Angeles', now()))::date - i;
    -- ⚠️ i * 7919 mod 1000 walks 919, 838, 757, 676 … — it steps down by 81 every day, so
    -- consecutive days land on the same side of every threshold and the first three days
    -- of history are all hard sessions in a row. A hash of the day gives an actual spread.
    v_seed := (hashtext(d::text) & 2147483647) / 2147483647.0;
    -- ⚠️ A fixed daily intake against a near-fixed burn puts every one of the eighty-four
    -- days in the same bucket: with 1,550 in and 1,900 out the heat map on 11 came out
    -- solid DEFICIT, and with 1,950 in it came out solid LEVEL. The day-to-day swing is
    -- what makes the map worth drawing — 0.90 to 1.48 spans −520 to +380 kcal, which is
    -- the three tiers plus the recomp window 09's footnote counts.
    v_scale := 0.90 + ((hashtext(d::text || 'kcal') & 2147483647) / 2147483647.0) * 0.58;
    -- ⚠️ The day stops at the last tick that has actually happened. Generating the rest of
    -- today would put readings in the future, and the panel's HR row reads the newest tick.
    for t in select generate_series(
        (d + time '04:00') at time zone 'America/Los_Angeles',
        least((d + 1 + time '04:00') at time zone 'America/Los_Angeles' - interval '5 minutes',
              date_trunc('hour', now()) + interval '5 minutes'
                * floor(extract(minute from now()) / 5)),
        interval '5 minutes')
    loop
      -- ⚠️ 13 板 · a resting tick is HR ≤ RHR+5 AND met < 1.2 AND steps = 0, and the whole
      -- battery hangs off how many of those a day contains: a resting tick nets +0.10
      -- (0.25 charge_rest against half the 0.30 basal) while an ordinary seated tick nets
      -- −0.30. Sprinkle a few steps onto every five-minute block and nothing is ever
      -- resting, so the battery falls to the floor by dinner every single day.
      --
      -- The seated band therefore straddles RHR+5 on purpose: the night sits at 47–53 so
      -- the 5th percentile lands near 47, and the desk sits at 50–58, which puts a little
      -- under a third of the seated day under the line. That is what holds the
      -- 21-day chain inside a human range instead of pinning at 0 or 100.
      v_hour := extract(hour from t at time zone 'America/Los_Angeles')::int;
      v_minute := extract(minute from t at time zone 'America/Los_Angeles')::int;
      v_walk := v_hour = 7 and v_minute < 35;
      v_train := v_hour = 18 and v_minute < 45 and v_seed > 0.30;
      -- asleep 00:00 → 06:29. In the 04:00 day frame that is the tail of last night at the
      -- start and the head of tonight at the end — one night split across two user days,
      -- which is exactly the case the 04:00 cut exists to handle.
      v_asleep := v_hour * 60 + v_minute < 390;

      v_hr := case
        when v_asleep then 47 + (random() * 6)::int
        when v_walk then 96 + (random() * 14)::int
        -- ⚠️ TRAINING_LOAD is 21·(1−e^(−RAW/60)) and it saturates fast: 45 minutes at Z4
        -- already spends 135 raw and lands at 18.5, a hair off the 20.9 cap. A person who
        -- trains at Z4 every evening reads as 19 out of 21 every single day, which makes
        -- RECENT LOAD say HEAVY forever and the ring meaningless. Most sessions sit in Z3
        -- (124–145 bpm here, given RHR 47 and HR_MAX 187), which is 54 raw and lands on
        -- 12.4 — the number board 04 prints.
        when v_train and v_seed > 0.75 then 148 + (random() * 16)::int
        when v_train then 126 + (random() * 16)::int
        -- the ordinary day: mostly still at a desk, moving for part of each hour
        when random() < 0.12 then 76 + (random() * 16)::int
        else round(50 + random() * 9.5)::int
      end;
      v_moving := v_walk or v_train or v_hr > 70;
      v_met := case
        when v_asleep then 0.95
        when v_moving then greatest(1.0, v_hr / 62.0)
        else 1.0
      end;

      insert into public.raw_samples
        (user_id, ts, sampled_tz, day_offset, calendar_day, heart, step, cal, met, stress,
         sleep_states, src)
      values (v_user, t, 'America/Los_Angeles', 0, d, v_hr,
              case when v_asleep then 0
                   when v_walk then 520 + (random() * 90)::int
                   when v_train then 40 + (random() * 60)::int
                   when v_moving then 60 + (random() * 140)::int
                   else 0 end,
              case when v_asleep then 4 else 3 + (random() * 9)::int end,
              round(v_met, 2),
              -- stressValue idles around 30 on a seated wrist; the 40 dead zone in the
              -- drain term exists precisely so that idle does not bill a line every tick.
              case when v_asleep then 18 + (random() * 10)::int
                   when v_train then 55 + (random() * 25)::int
                   -- a rough couple of hours after lunch, which is where the stress row
                   -- on 13 comes from: the 40 dead zone means an ordinary desk never bills
                   when v_hour between 14 and 15 then 52 + (random() * 20)::int
                   when v_moving then 34 + (random() * 16)::int
                   else 26 + (random() * 12)::int end,
              -- 1 deep · 2 light · 3 awake in bed · 0 not asleep
              case when v_hour between 1 and 2 then 1
                   when v_asleep and random() < 0.06 then 3
                   when v_asleep then 2
                   else 0 end,
              'band')
      on conflict do nothing;
    end loop;

    -- sleep is an input only; it never reaches the screen
    -- Kept consistent with the tick stream above: 00:00–06:29 is 390 minutes, of which
    -- 01:00–02:59 reads deep. A total that disagrees with the ticks would settle a day
    -- whose curve says something else.
    --
    -- ⚠️ Only the last fourteen days have nights. The band is new in this demo — the weight and
    -- food history came from Health and from typing, which is a real shape of account and
    -- the one board 13's empty state is written for.
    --
    -- It also bounds the reserve chain. BB(t) chains each day's anchor to the previous
    -- day's close and board 13's model has no restoring term: charge and drain are two
    -- independent sums, so any day whose sums do not cancel walks the level until a clamp
    -- catches it. The board's own printed day is +12 (+38 −14 −9 −3), which reaches 100 in
    -- eight days. Fourteen nights climbing off the cold-start 20 lands BB_WAKE in the
    -- seventies, which is where every design board sits and which selects the 14.5 target
    -- they all print — without pretending the model has a fixed point it does not have.
    -- Fourteen is also the number 13's confidence copy is written around.
    if i <= 13 then
      insert into public.sleep_nights (user_id, user_day, total_minutes, deep_minutes, light_minutes, wake_count)
      values (v_user, d, 390, 120, 250, (random() * 3)::int)
      on conflict (user_id, user_day) do nothing;
    end if;

    -- meals: most days logged, some days with a gap, one fasted day a fortnight.
    -- ⚠️ Today is always logged and always filtered to the meals that have already
    -- happened, so the current day lands in PARTIAL — the state board 04's default screen
    -- is drawn in, and the one the whole fuel flow is written around.
    if v_seed > 0.14 or i = 0 then
      insert into public.meals (user_id, user_day, slot, logged_at, text_input, kcal, protein_g, carb_g, fat_g, confidence, model_version, client_op_id)
      select v_user, d, m.slot, m.at, m.text, m.kcal, m.p, m.c, m.f, m.conf, 'seed', extensions.gen_random_uuid()
      from (values
        ('BREAKFAST', (d + time '07:20') at time zone 'America/Los_Angeles',
         'OATS · WHEY · BLUEBERRIES', round((300 + random() * 50) * v_scale)::int, 32, 34, 8, 'HIGH'),
        ('LUNCH', (d + time '12:40') at time zone 'America/Los_Angeles',
         'CHICKEN · RICE · GREENS', round((450 + random() * 90) * v_scale)::int, 44, 46, 14, 'MEDIUM'),
        ('DINNER', (d + time '19:40') at time zone 'America/Los_Angeles',
         'SALMON · POTATO · BROCCOLI', round((480 + random() * 120) * v_scale)::int, 46, 42, 18, 'MEDIUM')
      ) as m(slot, at, text, kcal, p, c, f, conf)
      where m.at <= now()
      on conflict do nothing;
      if v_seed > 0.55 then
        insert into public.meals (user_id, user_day, slot, logged_at, text_input, kcal, protein_g, carb_g, fat_g, confidence, model_version, client_op_id)
        select v_user, d, 'SNACK', (d + time '16:10') at time zone 'America/Los_Angeles',
               'GREEK YOGURT · ALMONDS', round((180 + random() * 50) * v_scale)::int, 22, 14, 8, 'HIGH', 'seed',
               extensions.gen_random_uuid()
        where (d + time '16:10') at time zone 'America/Los_Angeles' <= now()
        on conflict do nothing;
      end if;
    end if;

    -- a weigh-in most mornings, with a BIA reading every other day
    if v_seed > 0.22 then
      insert into public.weigh_ins (user_id, measured_at, sampled_tz, weight_kg, source, client_op_id)
      values (v_user, (d + time '06:40') at time zone 'America/Los_Angeles',
              'America/Los_Angeles', round((75.6 - i * 0.017 + (random() - 0.5) * 0.6)::numeric, 2),
              case when v_seed > 0.6 then 'health' else 'manual' end, extensions.gen_random_uuid());

      if v_seed > 0.4 then
        insert into public.body_composition
          (user_id, measured_at, user_day, measurement_source, input_weight_kg,
           body_fat_pct, fat_mass_kg, lean_body_mass_kg, bmr_kcal, derived_fields)
        values (v_user, (d + time '06:45') at time zone 'America/Los_Angeles', d, 'device_bia',
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
