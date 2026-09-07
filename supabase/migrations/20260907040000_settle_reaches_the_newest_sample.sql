-- 每次有新数据都算到最新那一笔。
--
-- 触发这一半早就对了：raw_samples 上的 nb.on_calculation_fact 每插一行就
-- nb.invalidate_calculation，把那天标脏，而 recompute_range 的跳过条件末尾是
-- `and (w.dirty_from is null or d<w.dirty_from)` —— 脏天永远不跳过。所以一次同步
-- 落地就会重算。
--
-- 错的是**地平线**。两道 5 分钟的截断叠在一起：
--   1. recompute_range 把结算时钟 tick 量化到 now() 的 5 分钟桶，calculation_instant
--      就是这个桶；
--   2. reserve_replay_uncached 的 tick_grid 又收在
--      `date_bin(5min, calculation_instant) - interval '5 minutes'`，再砍掉一格。
-- 于是 10:07 结算，时钟取 10:05，身体电量的格子只画到 10:00：10:00 之后的采样已经
-- 在服务器上，却要再等 5–10 分钟才进得了数字。训练负荷只受第 1 条影响（它的上界是
-- least(day_end, calculation_instant)，没有多砍一格），丢 0–5 分钟。
--
-- 这里改三处，公式一个字不动：
--   A. tick 从 5 分钟桶降到 1 分钟桶 —— 结算时钟贴住墙上时钟。
--   B. 跳过条件从「同一个 tick」换成「距上次结算不足 5 分钟且这天不脏」。这是 A 的
--      配套：没有 B，一个 1 分钟的 tick 会让每次空转的同步都重放一整天（6–15 s）。
--      有了 B，空闲时的重算频率跟今天完全一样（最快 5 分钟一次），而有新数据时照旧
--      立刻重算 —— 走的是脏天那条路，不受这个窗口限制。
--   C. 身体电量的 tick_grid 末端取「上一个完整格子」与「最后一个真有采样的格子」中
--      较晚的那个。地平线因此由数据决定而不是由时钟决定；数据本身带 input_revision，
--      所以重放依旧可复现。
--
-- calculation_status.pending 必须跟 B 严格互补，否则今天这一行会永远显示 pending。
-- 两边都用「5 分钟」这一个窗口，一个取 >，一个取 <=。
--
-- 按 20260906221000 / 20260907010000 的做法在生产函数体上做文本替换，这样它叠在最后
-- 一次改动之上；每个锚点必须命中一次。

-- ------------------------------------------------------------------ A + B · 结算时钟

do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.recompute_range(uuid,date,date,text)'::regprocedure);
 if position('interval ''1 minute'',now()' in def)>0 then return; end if;

 -- A · 1 分钟的结算时钟。
 patched:=replace(def,
  'tick:=least(hi,date_bin(interval ''5 minutes'',now(),''2000-01-01''::timestamptz));',
  'tick:=least(hi,date_bin(interval ''1 minute'',now(),''2000-01-01''::timestamptz));');
 if patched=def then raise exception 'SETTLE_TICK_ANCHOR_MISSING'; end if; def:=patched;

 -- B · 「同一个 tick」→「还新鲜」。脏天不受影响，它在同一个 exists 的最后一行被排除。
 patched:=replace(def,
  'and r.calculation_as_of=tick and r.profile_revision=profile_rev',
  'and r.calculation_as_of>tick-interval ''5 minutes'' and r.profile_revision=profile_rev');
 if patched=def then raise exception 'SETTLE_FRESHNESS_ANCHOR_MISSING'; end if; def:=patched;

 execute def;
end $$;

-- ------------------------------------------------------------- pending · B 的互补面

-- ⚠️ 不能 create or replace：calculation_status 自 20260904085910 起被 20260906130331
-- （bb-2.1）、20260906131708（tl-2.2）和 20260906221000（energy-1.1）文本补丁改过版本
-- 谓词。整份重写会把那些版本号一起回滚。所以这里也只替换那一个时钟表达式。
--
-- 与 recompute_range 的跳过条件互补：那边「> tick − 5 分钟」就跳过，这边「<=」就是
-- pending。
--
-- ⚠️ 新鲜度窗口只能作用在还在走的今天。原来的 least(ends_at, 时钟) 靠严格的 `<` 把
-- 已收尾的历史日挡在外面：那些日子 as_of 正好停在 ends_at。换成 `<=` 之后 least 仍然
-- 取到 ends_at，于是 `ends_at <= ends_at` 成立，每一个历史日都变成永久 pending
-- （calculation_revisions 第 11 条会红）。所以拆成两个条件：这天还没收尾，且距上次
-- 结算已满五分钟。
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('public.calculation_status(date,date)'::regprocedure);
 if position('interval ''1 minute'',now()' in def)>0 then return; end if;

 patched:=replace(def,
  'r.calculation_as_of<least(b.ends_at,date_bin(interval ''5 minutes'',now(),''2000-01-01''::timestamptz))',
  'r.calculation_as_of<b.ends_at and r.calculation_as_of<=date_bin(interval ''1 minute'',now(),''2000-01-01''::timestamptz)-interval ''5 minutes''');
 if patched=def then raise exception 'PENDING_WINDOW_ANCHOR_MISSING'; end if; def:=patched;

 execute def;
end $$;

-- ------------------------------------------------------- C · 身体电量的重放地平线

do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.reserve_replay_uncached(uuid,date)'::regprocedure);
 if position('-- 末端由数据决定' in def)>0 then return; end if;

 patched:=replace(def,
  'least(v_hi - interval ''5 minutes'', date_bin(interval ''5 minutes'', nb.calculation_instant(p_user,p_user_day), v_lo) - interval ''5 minutes'')',
  '-- 末端由数据决定：上一个完整格子，或最后一个真有采样的格子，取较晚者。'||chr(10)||
  '      least(v_hi - interval ''5 minutes'', greatest('||chr(10)||
  '        date_bin(interval ''5 minutes'', nb.calculation_instant(p_user,p_user_day), v_lo) - interval ''5 minutes'','||chr(10)||
  '        coalesce((select max(date_bin(interval ''5 minutes'', s.ts, v_lo)) from public.raw_samples s'||chr(10)||
  '                  where s.user_id = p_user and s.ts >= v_lo'||chr(10)||
  '                    and s.ts <= nb.calculation_instant(p_user,p_user_day)), v_lo)))');
 if patched=def then raise exception 'RESERVE_HORIZON_ANCHOR_MISSING'; end if; def:=patched;

 execute def;
end $$;

do $$ begin
 execute 'revoke execute on function nb.recompute_range(uuid,date,date,text) from public,anon,authenticated';
 execute 'revoke execute on function nb.reserve_replay_uncached(uuid,date) from public,anon,authenticated';
end $$;
