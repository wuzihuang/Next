-- 20260907040000 · 每次有新数据都算到最新那一笔。
--
-- 两件事：重放的末端跟着最后一笔采样走（而不是停在上一个完整的 5 分钟格子）；
-- 跳过条件与 calculation_status.pending 用同一个 5 分钟窗口，严格互补。
begin;
select plan(9);

insert into auth.users(id) values('0a0a0a0a-0000-0000-0000-000000000001');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date)
 values('0a0a0a0a-0000-0000-0000-000000000001','UTC','male',180,'1990-01-01')
 on conflict(user_id) do nothing;

select set_config('nb.t_user','0a0a0a0a-0000-0000-0000-000000000001',true);
select set_config('nb.t_day',nb.user_day_of(now(),'UTC')::text,true);

-- 昨天也留一笔，用来守住「已收尾的日子不能变成永久 pending」。
insert into public.raw_samples(user_id,ts,sampled_tz,heart,met)
 values('0a0a0a0a-0000-0000-0000-000000000001',
        date_bin(interval '5 minutes',now(),'2000-01-01'::timestamptz)-interval '1 day','UTC',70,1.0);

-- 一笔落在“当前这一格”里的采样：格子还没走完，但数据已经在服务器上了。
insert into public.raw_samples(user_id,ts,sampled_tz,heart,met)
 values('0a0a0a0a-0000-0000-0000-000000000001',
        date_bin(interval '5 minutes',now(),'2000-01-01'::timestamptz),'UTC',72,1.1);

select set_config('request.jwt.claim.sub',current_setting('nb.t_user'),true);
set local role authenticated;
select ok(public.settle_now(0)>=1,'新采样让当天立刻结算');
reset role;

-- 1 · 地平线到得了最新那一笔。改动前末端是 date_bin(5min,now())−5min，够不到它。
select ok(
 (select max(r.ts) from nb.reserve_replay_uncached(
    current_setting('nb.t_user')::uuid,current_setting('nb.t_day')::date) r)
 >= date_bin(interval '5 minutes',now(),'2000-01-01'::timestamptz),
 '重放画到了最后一笔采样所在的格子');

-- 2 · 刚结算完不是 pending，也不会再空转一次。
set local role authenticated;
select ok(not (select c.pending from public.calculation_status(
   current_setting('nb.t_day')::date,current_setting('nb.t_day')::date) c),
 '刚结算完的当天不是 pending');
select is(public.settle_now(0),0,'没有新数据、且还新鲜，不重放');
reset role;

-- 3 · 又来一笔新数据 —— 哪怕还在新鲜窗口里，也照旧立刻重算。走的是脏天那条路。
insert into public.raw_samples(user_id,ts,sampled_tz,heart,met)
 values('0a0a0a0a-0000-0000-0000-000000000001',
        date_bin(interval '5 minutes',now(),'2000-01-01'::timestamptz)-interval '5 minutes','UTC',75,1.2);
set local role authenticated;
select is(public.settle_now(0),1,'新鲜窗口内的新数据仍然立刻重算');
reset role;

-- 4 · 时钟自己走了四分钟：还在窗口里，不重放。
update public.daily_results set calculation_as_of=calculation_as_of-interval '4 minutes'
 where user_id=current_setting('nb.t_user')::uuid and user_day=current_setting('nb.t_day')::date;
set local role authenticated;
select is(public.settle_now(0),0,'四分钟内不重放');
reset role;

-- 5 · 满五分钟：pending，下一次结算认领它。跳过条件与 pending 是同一个窗口的两面。
update public.daily_results set calculation_as_of=calculation_as_of-interval '1 minute'
 where user_id=current_setting('nb.t_user')::uuid and user_day=current_setting('nb.t_day')::date;
set local role authenticated;
select ok((select c.pending from public.calculation_status(
   current_setting('nb.t_day')::date,current_setting('nb.t_day')::date) c),
 '满五分钟的当天转 pending');
reset role;

-- 6 · 新鲜度窗口只作用于还在走的今天。已收尾的日子 as_of 停在 ends_at，若这里写成
--     least(ends_at, 时钟) <= …，每一个历史日都会变成永久 pending。
set local role authenticated;
select ok(public.settle_now(1)>=1,'昨天也结算了');
select ok(not (select bool_or(c.pending) from public.calculation_status(
   current_setting('nb.t_day')::date-1,current_setting('nb.t_day')::date-1) c),
 '已收尾的昨天不是 pending');
reset role;

select * from finish();
rollback;
