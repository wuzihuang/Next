-- ADR 0010 · 平衡检查从此落库。此前测量屏什么都不写（MeasureTakeover 的注释写明「没有表，
-- 不该在测量屏里顺手发明 schema」），结果是这个测量没有任何地方可以回看。
--
-- ⚠️ 只落摘要。逐拍 RR 序列不进这张表：呈现或解读心律波形在美国属于受监管产品，产品刻意
-- 不做。夜间 HRV 的 RMSSD 在 night_hrv，和这里的白天离散度不是同一个数，永远不要互相比。
create table public.balance_checks (
  id            uuid primary key default extensions.gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  measured_at   timestamptz not null,
  user_day      date not null,
  sampled_tz    text not null default 'UTC',
  -- AutonomicBalance.Lead。'even' 是真结论，不是缺值。
  lead          text not null check (lead in ('rest', 'drive', 'even')),
  -- 0–100，SD1 / (SD1 + SD2) 的百分数。drive 的一份是 100 减它，不另存。
  rest_share    smallint not null check (rest_share between 0 and 100),
  -- Poincaré 的两个半轴与整段 SDNN，毫秒。三个都存，因为屏幕上那个 SPREAD 日后改用哪一个
  -- 都不该回头重算历史；algo_version 说明当时用的是哪一套阈值。
  sd1_ms        numeric(6, 2) not null check (sd1_ms >= 0),
  sd2_ms        numeric(6, 2) not null check (sd2_ms >= 0),
  sdnn_ms       numeric(6, 2) not null check (sdnn_ms >= 0),
  heart_rate    smallint check (heart_rate between 25 and 220),
  -- 参与计算的区间数。AutonomicBalance.minimumIntervals = 12 是下限，低于它不出结论、
  -- 也就不会有行。
  beat_count    smallint not null check (beat_count >= 12),
  algo_version  text not null default 'poincare-1',
  client_op_id  uuid not null
);

-- 同一次测量重放多少次都只有一行。BodyCompositionQueue 一样的离线重放语义。
create unique index balance_checks_client_op
  on public.balance_checks (user_id, client_op_id);
create index balance_checks_user_measured_idx
  on public.balance_checks (user_id, measured_at desc);

alter table public.balance_checks enable row level security;
create policy balance_checks_select on public.balance_checks
  for select to authenticated using ((select auth.uid()) = user_id);
create policy balance_checks_insert on public.balance_checks
  for insert to authenticated with check ((select auth.uid()) = user_id);

grant select, insert on public.balance_checks to authenticated;

comment on table public.balance_checks is
  '一次平衡检查的摘要行。不存逐拍 RR 序列，不是心电，不与 night_hrv.rmssd_ms 可比。';

-- 加了域就要同时补上导出与删号，否则新表会成为账号删除的漏网数据。
create or replace function public.account_delete(confirm text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null then return jsonb_build_object('error', 'UNAUTHENTICATED'); end if;
  if confirm is distinct from 'DELETE' then return jsonb_build_object('error', 'E_SCHEMA'); end if;

  delete from public.screen_frames where user_id = v_user;
  delete from public.ai_turns where user_id = v_user;
  delete from public.analytics_events where user_id = v_user;
  delete from public.call_changes where user_id = v_user;
  delete from public.meals where user_id = v_user;
  delete from public.weigh_ins where user_id = v_user;
  delete from public.body_composition where user_id = v_user;
  delete from public.balance_checks where user_id = v_user;
  delete from public.oxygen_samples where user_id = v_user;
  delete from public.raw_samples where user_id = v_user;
  delete from public.reserve_samples where user_id = v_user;
  delete from public.sleep_nights where user_id = v_user;
  delete from public.night_hrv where user_id = v_user;
  delete from public.daily_results where user_id = v_user;
  delete from public.sync_runs where user_id = v_user;
  delete from public.device_capabilities where user_id = v_user;
  delete from public.devices where user_id = v_user;
  delete from public.profiles where user_id = v_user;
  delete from auth.users where id = v_user;
  return jsonb_build_object('deleted', true);
end;
$$;

create or replace function public.export_all()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.user_id = (select auth.uid())),
    'days', (select coalesce(jsonb_agg(to_jsonb(d) order by d.user_day), '[]'::jsonb)
             from public.daily_results d where d.user_id = (select auth.uid())),
    'weigh_ins', (select coalesce(jsonb_agg(to_jsonb(w) order by w.measured_at), '[]'::jsonb)
                  from public.weigh_ins w where w.user_id = (select auth.uid())),
    'composition', (select coalesce(jsonb_agg(to_jsonb(b) order by b.measured_at), '[]'::jsonb)
                    from public.body_composition b where b.user_id = (select auth.uid())),
    'balance_checks', (select coalesce(jsonb_agg(to_jsonb(c) order by c.measured_at), '[]'::jsonb)
                       from public.balance_checks c where c.user_id = (select auth.uid())),
    'night_hrv', (select coalesce(jsonb_agg(to_jsonb(h) order by h.user_day), '[]'::jsonb)
                  from public.night_hrv h where h.user_id = (select auth.uid())),
    'oxygen_samples', (select coalesce(jsonb_agg(to_jsonb(o) order by o.ts), '[]'::jsonb)
                       from public.oxygen_samples o where o.user_id = (select auth.uid())),
    'meals', (select coalesce(jsonb_agg(to_jsonb(m) order by m.logged_at), '[]'::jsonb)
              from public.meals m where m.user_id = (select auth.uid()) and m.deleted_at is null));
$$;
