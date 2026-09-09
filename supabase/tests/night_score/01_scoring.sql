\set ON_ERROR_STOP on
set client_min_messages = warning;

-- ---------------------------------------------------------------- fixtures
create or replace function t_user(p_name text) returns uuid language plpgsql as $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users(id) values (u);
  insert into public.profiles(user_id, timezone) values (u, 'Asia/Shanghai');
  return u;
end $$;

-- A night with a real stage line: deep / light / REM / awake runs adding to `total`.
create or replace function t_night(u uuid, d date, total int, deep int, wakes int,
                                   line text default null, bed time default '23:30')
returns void language sql as $$
  insert into public.sleep_nights(user_id, user_day, total_minutes, deep_minutes,
                                  light_minutes, wake_count, sleep_line, sleep_start, wake_at)
  values (u, d, total, deep, total - deep, wakes, line,
          ((d - case when bed >= time '18:00' then 1 else 0 end)::text || ' ' || bed::text)::timestamp at time zone 'Asia/Shanghai',
          (((d - case when bed >= time '18:00' then 1 else 0 end)::text || ' ' || bed::text)::timestamp at time zone 'Asia/Shanghai')
            + make_interval(mins => total))
  on conflict (user_id, user_day) do update set
    total_minutes = excluded.total_minutes, deep_minutes = excluded.deep_minutes,
    light_minutes = excluded.light_minutes, wake_count = excluded.wake_count,
    sleep_line = excluded.sleep_line, sleep_start = excluded.sleep_start,
    wake_at = excluded.wake_at;
$$;

create or replace function t_rhr(u uuid, d date, rhr int) returns void language sql as $$
  insert into public.raw_samples(user_id,ts,heart)
  select u,sleep_start+make_interval(mins=>g*15),rhr
  from public.sleep_nights,generate_series(1,2) g where user_id=u and user_day=d
  on conflict(user_id,ts,src) do update set heart=excluded.heart;
  with r as (
    insert into public.daily_results(user_id, user_day) values (u, d)
    on conflict (user_id, user_day) do update set user_day = excluded.user_day returning id)
  insert into public.reserve_daily(result_id, night_inputs)
  select id, jsonb_build_object('rhr', rhr) from r
  on conflict (result_id) do update set night_inputs = excluded.night_inputs;
$$;

create or replace function t_spo2(u uuid, d date, lo int, hi int) returns void language sql as $$
  insert into public.oxygen_samples(user_id, ts, spo2)
  select u, sn.sleep_start + make_interval(mins => g * 10),
         case when g = 3 then lo else hi end
  from public.sleep_nights sn, generate_series(1, 20) g
  where sn.user_id = u and sn.user_day = d
  on conflict do nothing;
$$;

create or replace function t_resp(u uuid, d date, bpm numeric) returns void language sql as $$
  update public.sleep_nights set raw = jsonb_build_object('respiration', jsonb_build_array(
      jsonb_build_object('ts', sleep_start, 'breaths_per_minute', bpm),
      jsonb_build_object('ts', sleep_start + interval '1 minute', 'breaths_per_minute', bpm)))
  where user_id = u and user_day = d;
$$;

create or replace function t_hrv(u uuid,d date,hrv numeric) returns void language sql as $$
  update public.sleep_nights set raw=raw||jsonb_build_object('hrv',jsonb_build_array(
    jsonb_build_object('ts',sleep_start,'rmssd_ms',hrv),
    jsonb_build_object('ts',sleep_start+interval '15 minutes','rmssd_ms',hrv)))
  where user_id=u and user_day=d;
  insert into public.raw_samples(user_id,ts,hrv)
  select u,sleep_start+make_interval(mins=>g*15),hrv
  from public.sleep_nights,generate_series(0,1) g where user_id=u and user_day=d
  on conflict(user_id,ts,src) do update set hrv=excluded.hrv;
  select nb.refresh_night_hrv(u,d);
$$;

create table t_out(name text, got jsonb);
create or replace function t_run(p_name text, u uuid, d date) returns void language plpgsql as $$
declare p record;
begin
  select * into p from nb.night_score_parts(u, d);
  insert into t_out values (p_name, to_jsonb(p));
end $$;

-- ---------------------------------------------------------------- cases
do $$
declare u uuid; v uuid; w uuid; x uuid; i int;
begin
  -- 1 · a good night, everything present, no history yet
  u := t_user('good');
  perform t_night(u, '2026-09-05', 450, 90, 1, '1:120,0:90,2:100,1:136,4:4');
  perform t_rhr(u, '2026-09-05', 58);
  perform t_spo2(u, '2026-09-05', 96, 98);
  perform t_resp(u, '2026-09-05', 15);
  perform t_hrv(u, '2026-09-05', 45);
  perform t_run('1 好夜 · 全输入', u, '2026-09-05');

  -- 2 · a short, fragmented night with no line and no physiology at all
  v := t_user('short');
  perform t_night(v, '2026-09-05', 300, 40, 4);
  perform t_run('2 短睡 · 无线无生理', v, '2026-09-05');

  -- 3 · never worn: no row at all
  w := t_user('absent');
  perform t_run('3 完全没戴', w, '2026-09-05');

  -- 4 · a row that exists but recorded nothing
  perform t_night(w, '2026-09-04', 0, 0, 0);
  perform t_run('4 有行但 0 分钟', w, '2026-09-04');

  -- 4b · 普通睡眠：有曲线但没有 stage 2 —— REM 是"没在测"，不是"没有"
  perform t_night(w, '2026-09-06', 440, 110, 2, '1:150,0:110,1:180');
  perform t_run('4b 普通睡眠 · 曲线无 REM', w, '2026-09-06');
  -- 4c · 同一夜若把 REM 当成 0 分会掉多少：精准睡眠版本作对照
  perform t_night(w, '2026-09-07', 440, 110, 2, '1:150,0:110,2:96,1:84');
  perform t_run('4c 精准睡眠 · 曲线有 REM', w, '2026-09-07');

  -- 5 · oversleep
  x := t_user('long');
  perform t_night(x, '2026-09-05', 660, 120, 1, '1:200,0:120,2:140,1:196,4:4');
  perform t_run('5 睡 11 小时', x, '2026-09-05');
end $$;

-- 6 · calibration + regularity: 20 nights of history, a personally-low RMSSD, steady bedtime
do $$
declare u uuid := t_user('calibrated'); i int;
begin
  for i in 1..20 loop
    perform t_night(u, ('2026-09-05'::date - i), 430, 85, 1, '1:150,0:85,2:95,1:100', '23:30');
    perform t_hrv(u, '2026-09-05'::date - i, 25);
    perform t_rhr(u, '2026-09-05'::date - i, 52);
  end loop;
  perform t_night(u, '2026-09-05', 440, 88, 1, '1:150,0:88,2:98,1:104', '23:40');
  perform t_hrv(u, '2026-09-05', 25);
  perform t_rhr(u, '2026-09-05', 52);
  perform t_run('6 校准后 · 个人 HRV 25ms 准时睡', u, '2026-09-05');

  -- 7 · same person, same physiology, but three hours late to bed
  perform t_night(u, '2026-09-05', 440, 88, 1, '1:150,0:88,2:98,1:104', '02:40');
  perform t_hrv(u, '2026-09-05', 25);
  perform t_rhr(u, '2026-09-05', 52);
  perform t_run('7 同一人 · 晚睡三小时', u, '2026-09-05');
end $$;

-- 8 / 9 · accurateType 0 files a real stage line with no stage-2 runs. REM is then an input
-- the firmware did not record, not a night without REM, so architecture must land exactly
-- where the identical night with no line at all lands.
do $$
declare u uuid := t_user('no-rem'); v uuid := t_user('no-line');
begin
  perform t_night(u, '2026-09-05', 450, 90, 1, '0:90,1:356,4:4');
  perform t_run('8 有线但无 REM 分期', u, '2026-09-05');
  perform t_night(v, '2026-09-05', 450, 90, 1, null);
  perform t_run('9 完全没有分期线', v, '2026-09-05');
end $$;

do $$
declare a numeric; b numeric;
begin
  select (got->>'architecture_score')::numeric into a from t_out where name like '8 %';
  select (got->>'architecture_score')::numeric into b from t_out where name like '9 %';
  if a is distinct from b then
    raise exception 'REM_ABSENT_SCORED_AS_ZERO: with line %, without line %', a, b;
  end if;
end $$;

-- 10 / 11 · sleep-v1.3: the bedtime median exists from the third prior canonical night.
-- Two prior nights leave regularity null and bed_median unpublished; three score it, and a
-- night 25 minutes off that three-night median still lands inside the ±30 full-marks band.
do $$
declare u uuid := t_user('third-night'); p record; i int;
begin
  for i in 1..2 loop
    perform t_night(u, ('2026-09-05'::date - i), 430, 85, 1, '1:150,0:85,2:95,1:100', '23:30');
  end loop;
  perform t_night(u, '2026-09-05', 440, 88, 1, '1:150,0:88,2:98,1:104', '23:55');
  perform t_run('10 两个历史夜 · 规律仍空', u, '2026-09-05');
  select * into p from nb.night_score_parts(u, '2026-09-05');
  if p.regularity_score is not null or p.inputs ? 'bed_median' or (p.inputs->>'baseline_bed_nights')::int <> 2 then
    raise exception 'REGULARITY_SCORED_BEFORE_THIRD_NIGHT: %', p.inputs;
  end if;

  perform t_night(u, '2026-09-02', 430, 85, 1, '1:150,0:85,2:95,1:100', '23:30');
  perform t_run('11 三个历史夜 · 规律出分', u, '2026-09-05');
  select * into p from nb.night_score_parts(u, '2026-09-05');
  if p.regularity_score is distinct from 100 or (p.inputs->>'bed_median')::int <> 330
     or (p.inputs->>'baseline_bed_nights')::int <> 3 then
    raise exception 'REGULARITY_NOT_SCORED_ON_THIRD_NIGHT: reg %, inputs %', p.regularity_score, p.inputs;
  end if;
end $$;
