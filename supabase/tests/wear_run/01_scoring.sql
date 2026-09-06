\set ON_ERROR_STOP on
set timezone to 'UTC';

create or replace function t_user() returns uuid language plpgsql as $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users(id) values (u);
  insert into public.profiles(user_id, timezone) values (u, 'UTC');
  return u;
end $$;

-- Fill `slots` completed five-minute bins from 04:00 UTC, `worn_slots` of them with a heart.
create or replace function t_ticks(u uuid, d date, slots int, worn_slots int)
returns void language plpgsql as $$
declare
  lo timestamptz := ((d + time '04:00') at time zone 'UTC');
  i int;
begin
  for i in 0..slots - 1 loop
    insert into public.raw_samples(user_id, ts, heart)
    values (u, lo + make_interval(mins => i * 5), case when i < worn_slots then 70 else null end);
  end loop;
end $$;

do $$
declare
  u uuid := t_user();
  d date := date '2026-08-20';
begin
  -- Closed day: 288 slots, 144 with heart → worn.
  perform t_ticks(u, d, 288, 144);
  insert into public.daily_results(user_id, user_day) values (u, d);
  if not (select worn from public.daily_results where user_id = u and user_day = d) then
    raise exception 'half coverage should be worn';
  end if;
  if (select wear_run from public.daily_results where user_id = u and user_day = d) <> 1 then
    raise exception 'first worn day should be run 1';
  end if;
  if (select wear_miss from public.daily_results where user_id = u and user_day = d) <> 0 then
    raise exception 'live run miss should be 0';
  end if;

  -- Next day, no ticks → first miss.
  insert into public.daily_results(user_id, user_day) values (u, d + 1);
  if (select worn from public.daily_results where user_id = u and user_day = d + 1) then
    raise exception 'empty day is not worn';
  end if;
  if (select wear_run from public.daily_results where user_id = u and user_day = d + 1) <> 0 then
    raise exception 'broken run has no number';
  end if;
  if (select wear_miss from public.daily_results where user_id = u and user_day = d + 1) <> 1 then
    raise exception 'first miss should be amber';
  end if;

  -- Second empty day → cooled.
  insert into public.daily_results(user_id, user_day) values (u, d + 2);
  if (select wear_miss from public.daily_results where user_id = u and user_day = d + 2) <> 2 then
    raise exception 'second miss should be gray';
  end if;

  -- Worn again → restarts at 1, not a freeze of the old 1.
  perform t_ticks(u, d + 3, 288, 200);
  insert into public.daily_results(user_id, user_day) values (u, d + 3);
  if (select wear_run from public.daily_results where user_id = u and user_day = d + 3) <> 1 then
    raise exception 'amber is not a freeze';
  end if;

  -- A row with only temperature-less empty hearts on 143/288 is not worn (just under half).
  perform t_ticks(u, d + 4, 288, 143);
  insert into public.daily_results(user_id, user_day) values (u, d + 4);
  if (select worn from public.daily_results where user_id = u and user_day = d + 4) then
    raise exception '143 of 288 must not be a worn day';
  end if;

  -- Nightstand: step 0 and no heart is not wrist evidence.
  insert into public.raw_samples(user_id, ts, heart, step)
  select u, ((d + 5 + time '04:00') at time zone 'UTC') + make_interval(mins => g * 5),
         null, 0
  from generate_series(0, 287) g;
  insert into public.daily_results(user_id, user_day) values (u, d + 5);
  if (select worn from public.daily_results where user_id = u and user_day = d + 5) then
    raise exception 'zero-step empty-heart ticks are not worn';
  end if;

  -- Everyday daytime: 08:00–23:00 is 180 of 288.
  insert into public.raw_samples(user_id, ts, heart)
  select u, ((d + 6 + time '04:00') at time zone 'UTC') + make_interval(mins => g * 5), 70
  from generate_series(48, 227) g;
  insert into public.daily_results(user_id, user_day) values (u, d + 6);
  if not (select worn from public.daily_results where user_id = u and user_day = d + 6) then
    raise exception '08-23 wear should be a worn day';
  end if;

  -- Short daytime: 09:00–20:00 is 132 of 288.
  insert into public.raw_samples(user_id, ts, heart)
  select u, ((d + 7 + time '04:00') at time zone 'UTC') + make_interval(mins => g * 5), 70
  from generate_series(60, 191) g;
  insert into public.daily_results(user_id, user_day) values (u, d + 7);
  if (select worn from public.daily_results where user_id = u and user_day = d + 7) then
    raise exception '09-20 wear must not be a worn day';
  end if;
  if (select wear_miss from public.daily_results where user_id = u and user_day = d + 7) <> 1 then
    raise exception 'a closed miss after a worn day is amber';
  end if;

  -- A missing calendar yesterday breaks the run instead of skipping the hole.
  insert into public.raw_samples(user_id, ts, heart)
  select u, ((d + 9 + time '04:00') at time zone 'UTC') + make_interval(mins => g * 5), 70
  from generate_series(0, 199) g;
  insert into public.daily_results(user_id, user_day) values (u, d + 9);
  if (select wear_run from public.daily_results where user_id = u and user_day = d + 9) <> 1 then
    raise exception 'a hole in user_day must restart the run';
  end if;
end $$;
