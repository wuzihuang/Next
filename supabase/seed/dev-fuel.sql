-- Marked meals, weigh-ins and body-composition readings for ONE real account, so the fuel
-- and composition charts have something to draw while the band supplies the rest. Every row
-- carries a marker; the cleanup block at the end removes exactly these rows.
--   meals.model_version = 'seed' · weigh_ins.health_uuid like 'seed-%' · body_composition.derived_fields @> '{seed}'
do $$
declare
  v_email text := '821819569@qq.com';
  v_user uuid; v_tz text; v_today date; d date; i int; v_seed numeric; v_wkg numeric; v_fat numeric;
begin
  select id into v_user from auth.users where email = v_email;
  if v_user is null then raise exception 'no user %', v_email; end if;
  select timezone into v_tz from public.profiles where user_id = v_user;
  v_tz := coalesce(v_tz, 'Asia/Shanghai');
  v_today := nb.user_day_of(now(), v_tz);

  for i in 0..6 loop
    d := v_today - i;
    v_seed := (hashtext(d::text) & 2147483647) / 2147483647.0;
    if v_seed > 0.2 or i = 0 then
      insert into public.meals (user_id, user_day, slot, logged_at, text_input, kcal, protein_g, carb_g, fat_g, confidence, model_version, client_op_id)
      select v_user, d, m.slot, m.at, m.text, m.kcal, m.p, m.c, m.f, 'HIGH', 'seed', extensions.gen_random_uuid()
      from (values
        ('BREAKFAST', (d + time '07:20') at time zone v_tz, 'OATS · EGGS · MILK',        380 + (i * 17) % 60, 28, 44, 12),
        ('LUNCH',     (d + time '12:40') at time zone v_tz, 'CHICKEN · RICE · BROCCOLI', 560 + (i * 31) % 90, 48, 60, 14),
        ('DINNER',    (d + time '19:40') at time zone v_tz, 'SALMON · POTATO · GREENS',  610 + (i * 23) % 80, 46, 46, 22)
      ) as m(slot, at, text, kcal, p, c, f)
      where m.at <= now()
      on conflict do nothing;
    end if;
  end loop;

  -- ten weeks of body composition, one reading a week, fat drifting down the CUT way
  for i in 0..9 loop
    d := v_today - 3 - i * 7;
    v_wkg := round((96.6 + i * 0.12)::numeric, 2);
    v_fat := round((32.1 + i * 0.09 + (case when i % 3 = 1 then -0.15 else 0.05 end))::numeric, 2);
    insert into public.weigh_ins (user_id, measured_at, sampled_tz, weight_kg, source, health_uuid, client_op_id)
    values (v_user, (d + time '06:40') at time zone v_tz, v_tz, v_wkg, 'manual', 'seed-' || d::text, extensions.gen_random_uuid())
    on conflict do nothing;
    insert into public.body_composition
      (user_id, measured_at, user_day, measurement_source, input_weight_kg, body_fat_pct, fat_mass_kg, lean_body_mass_kg, bmr_kcal, derived_fields)
    values (v_user, (d + time '06:45') at time zone v_tz, d, 'manual', v_wkg, v_fat,
            round((v_wkg * v_fat / 100)::numeric, 2), round((v_wkg * (1 - v_fat / 100))::numeric, 2), 2208, '{seed}');
  end loop;

  perform nb.recompute_range(v_user, v_today - 7, v_today, 'seed-fuel');
end $$;

-- ---------------------------------------------------------------- cleanup
-- do $$
-- declare v_user uuid; v_tz text; v_today date;
-- begin
--   select id into v_user from auth.users where email = '821819569@qq.com';
--   select timezone into v_tz from public.profiles where user_id = v_user;
--   v_today := nb.user_day_of(now(), coalesce(v_tz, 'Asia/Shanghai'));
--   delete from public.meals            where user_id = v_user and model_version = 'seed';
--   delete from public.weigh_ins        where user_id = v_user and health_uuid like 'seed-%';
--   delete from public.body_composition where user_id = v_user and derived_fields @> '{seed}';
--   perform nb.recompute_range(v_user, v_today - 7, v_today, 'seed-fuel-cleanup');
-- end $$;
