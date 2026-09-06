\set ON_ERROR_STOP on
set client_min_messages = notice;
do $$
declare u uuid := t_user('lifecycle'); n int; s int; off1 numeric; off2 numeric;
begin
  -- evening_offset must treat 23:40 and 01:20 as 100 minutes apart, not 22 hours
  off1 := nb.evening_offset('2026-09-04 23:40+08'::timestamptz, 'Asia/Shanghai');
  off2 := nb.evening_offset('2026-09-05 01:20+08'::timestamptz, 'Asia/Shanghai');
  assert abs(off2 - off1) = 100, format('evening_offset 跨午夜错了: %s vs %s', off1, off2);
  raise notice '✅ evening_offset 跨午夜: 23:40=%, 01:20=% (差 % 分钟)', off1, off2, off2-off1;

  perform t_night(u, '2026-09-05', 450, 90, 1, '1:120,0:90,2:100,1:136,4:4');
  perform nb.refresh_night_score(u, '2026-09-05');
  select count(*), max(score) into n, s from public.night_score where user_id = u;
  assert n = 1, '应写入一行';
  raise notice '✅ refresh 写入 1 行, score=%, version=%', s,
    (select score_version from public.night_score where user_id = u);

  -- re-running must update in place, not duplicate
  perform t_night(u, '2026-09-05', 300, 40, 4);
  perform nb.refresh_night_score(u, '2026-09-05');
  select count(*), max(score) into n, s from public.night_score where user_id = u;
  assert n = 1, '重跑不应新增行';
  raise notice '✅ 重跑就地更新: 仍 1 行, score 变为 %', s;

  -- a night that loses its record must lose its score, not keep yesterday's number
  delete from public.sleep_nights where user_id = u and user_day = '2026-09-05';
  perform nb.refresh_night_score(u, '2026-09-05');
  select count(*) into n from public.night_score where user_id = u;
  assert n = 0, '记录消失后分数应被删除';
  raise notice '✅ 记录消失 → 分数行被删除';

  -- recompute_range must drive it
  perform t_night(u, '2026-09-05', 450, 90, 1, '1:120,0:90,2:100,1:136,4:4');
  perform t_night(u, '2026-09-04', 400, 80, 2, '1:120,0:80,2:90,1:110');
  perform nb.recompute_range(u, '2026-09-04', '2026-09-05', 'test');
  select count(*) into n from public.night_score where user_id = u;
  assert n = 2, format('recompute_range 应结算 2 夜, 实际 %s', n);
  raise notice '✅ recompute_range 结算了 % 夜', n;

  -- the client may read but never write
  assert has_table_privilege('authenticated', 'public.night_score', 'select'), '应可读';
  assert not has_table_privilege('authenticated', 'public.night_score', 'insert'), '不应可写';
  raise notice '✅ authenticated: 可 select, 不可 insert';
end $$;
