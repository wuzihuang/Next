-- Per-tick sleep stages for last night, so 07 · 12's hypnogram has a real shape to draw.
-- The band writes `sleep_nights` (a summary) but this build is not writing `sleep_states`
-- tick by tick, so the lanes have nothing to lay out. Marked `src = 'seed-sleep'`; the
-- cleanup at the end removes exactly these rows and nothing the band wrote.
--   1 deep · 2 light · 3 awake in bed · 0 not asleep
do $$
declare
  v_user uuid; v_tz text; v_today date; t timestamptz; v_min int; v_state smallint;
begin
  select id into v_user from auth.users where email = '821819569@qq.com';
  select timezone into v_tz from public.profiles where user_id = v_user;
  v_tz := coalesce(v_tz, 'Asia/Shanghai');
  v_today := nb.user_day_of(now(), v_tz);

  for t in select generate_series(
      ((v_today - 1) + time '23:41') at time zone v_tz,
      (v_today + time '07:18') at time zone v_tz,
      interval '5 minutes')
  loop
    v_min := (extract(epoch from t - (((v_today - 1) + time '23:41') at time zone v_tz)) / 60)::int;
    -- awake settling, then two deep blocks before 3am, light between, a short wake at 05:10
    v_state := case
      when v_min < 18 then 3
      when v_min between 60 and 167 then 1
      when v_min between 210 and 253 then 1
      when v_min between 328 and 341 then 3
      else 2
    end;
    insert into public.raw_samples (user_id, ts, sampled_tz, sleep_states, src)
    values (v_user, t, v_tz, v_state, 'seed-sleep')
    on conflict do nothing;
  end loop;
end $$;

-- ---------------------------------------------------------------- cleanup
-- delete from public.raw_samples
--  where src = 'seed-sleep'
--    and user_id = (select id from auth.users where email = '821819569@qq.com');
