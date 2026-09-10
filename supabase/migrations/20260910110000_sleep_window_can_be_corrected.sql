-- #28 · the wrist is often wrong about when the night began, and the person wearing it is
-- not. This gives that person the start and the end of one night, and nothing else.
--
-- The correction is an override, never an edit of what the band filed. `corrected_start` /
-- `corrected_end` hold what the user said; a BEFORE trigger publishes them as the row's
-- `sleep_start` / `wake_at` and files the band's own window into `raw.recorded_start` /
-- `raw.recorded_end` on its way past. Every reader — the phone's own select, the sleep
-- score, `canonical_sleep_nights`, `sleep_windows`, the Body Battery night — reads
-- `sleep_start` / `wake_at` and therefore reads the correction without knowing about it.
-- That is the whole reason the override lives in this row rather than in a table beside
-- it: one seam, and the three surfaces cannot disagree.
--
-- ⚠️ The correction moves the *window*, not the stage line. The band's minutes keep the
-- clock times it recorded them at, so a corrected window clips them and never shifts them.
-- `sleep_evidence_minutes` therefore anchors the offset line on `raw.recorded_start` and
-- filters by the published window. A window stretched earlier than the band's own gains
-- room and no sleep: minutes with no record stay minutes with no record, which is what
-- keeps a correction from being a way to invent a night.
-- ⚠️ And a correction that contains no recorded sleep at all is refused outright
-- (WINDOW_HAS_NO_SLEEP) rather than published as a night of nothing. The night either
-- rests on the band's evidence or it is not a night.
-- ⚠️ The next sync does not win. It brings a new band window, the trigger files that as
-- the recorded one, and the published window stays the user's until they clear it.

alter table public.sleep_nights
  add column if not exists corrected_start timestamptz,
  add column if not exists corrected_end   timestamptz,
  add column if not exists corrected_at    timestamptz;

do $do$
begin
  if not exists(select 1 from pg_constraint where conname='sleep_nights_correction_is_a_window') then
    alter table public.sleep_nights add constraint sleep_nights_correction_is_a_window
      check ((corrected_start is null) = (corrected_end is null)
             and (corrected_start is null or corrected_end > corrected_start));
  end if;
end $do$;

comment on column public.sleep_nights.corrected_start is
  'The start the user asserted for this night, local wall clock resolved to an instant.
   Null means the published window is the band own. See #28.';
comment on column public.sleep_nights.corrected_end is
  'The end the user asserted. Published as wake_at; the band window moves to raw.recorded_end.';
comment on column public.sleep_nights.corrected_at is
  'When the correction was made. Present only while a correction stands.';

-- The trigger fires after `preserve_sleep_hrv_revisions` (p sorts before s, and Postgres
-- fires same-timing triggers by name), so
-- the HRV merge still sees the band's own window and keeps every point it recorded. Only
-- the published window narrows.
create or replace function nb.publish_sleep_correction() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.corrected_start is not null then
    -- Remember the window the band filed — on the first correction, and again every time
    -- a sync brings a new one. An update that only touches the correction columns leaves
    -- sleep_start alone, and that is how this tells the two apart.
    if new.sleep_start is not null and new.wake_at is not null
       and (tg_op = 'INSERT'
            or new.sleep_start is distinct from old.sleep_start
            or new.wake_at is distinct from old.wake_at
            or not (coalesce(new.raw,'{}'::jsonb) ? 'recorded_start')) then
      new.raw := coalesce(new.raw,'{}'::jsonb) || jsonb_build_object(
        'recorded_start', new.sleep_start, 'recorded_end', new.wake_at,
        'recorded_total_minutes', new.total_minutes, 'recorded_deep_minutes', new.deep_minutes,
        'recorded_light_minutes', new.light_minutes, 'recorded_wake_count', new.wake_count);
    end if;
    new.sleep_start := new.corrected_start;
    new.wake_at     := new.corrected_end;
    new.corrected_at := coalesce(new.corrected_at, now());
  elsif coalesce(new.raw,'{}'::jsonb) ? 'recorded_start' then
    -- Cleared. The band's window comes back out of the receipt it was filed in.
    new.sleep_start := coalesce(nb.bb_instant(new.raw->>'recorded_start'), new.sleep_start);
    new.wake_at     := coalesce(nb.bb_instant(new.raw->>'recorded_end'), new.wake_at);
    new.total_minutes := coalesce((new.raw->>'recorded_total_minutes')::smallint, new.total_minutes);
    new.deep_minutes  := coalesce((new.raw->>'recorded_deep_minutes')::smallint, new.deep_minutes);
    new.light_minutes := coalesce((new.raw->>'recorded_light_minutes')::smallint, new.light_minutes);
    new.wake_count    := coalesce((new.raw->>'recorded_wake_count')::smallint, new.wake_count);
    new.raw := new.raw - 'recorded_start' - 'recorded_end' - 'recorded_total_minutes'
             - 'recorded_deep_minutes' - 'recorded_light_minutes' - 'recorded_wake_count';
    new.corrected_at := null;
  end if;
  return new;
end $$;

drop trigger if exists sleep_correction_wins on public.sleep_nights;
create trigger sleep_correction_wins
  before insert or update on public.sleep_nights
  for each row execute function nb.publish_sleep_correction();

-- The stage line is anchored where the band recorded it, and only the window moves.
do $do$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.sleep_evidence_minutes(uuid,date)'::regprocedure);
  if position('recorded_start' in definition) > 0 then return; end if;

  -- One extra column on the night: where the offset line starts counting.
  patched := replace(definition,
    ' ), intervals as materialized (',
    ' ), anchored as materialized (
  select n.*,coalesce(nb.bb_instant(n.raw->>''recorded_start''),n.sleep_start) anchor_start,
         coalesce(nb.bb_instant(n.raw->>''recorded_end''),n.wake_at) anchor_end from night n
 ), intervals as materialized (');
  if patched = definition then raise exception 'SLEEP_MINUTES_NIGHT_ANCHOR_MISSING'; end if;
  definition := patched;

  -- The legacy line's minute grid is the recorded night, not the published one.
  patched := replace(definition,
    'select g.t,row_number() over(order by g.t)-1 from night n
  cross join lateral generate_series(n.sleep_start,n.wake_at-interval ''1 minute'',interval ''1 minute'') g(t)',
    'select g.t,row_number() over(order by g.t)-1 from anchored n
  cross join lateral generate_series(n.anchor_start,n.anchor_end-interval ''1 minute'',interval ''1 minute'') g(t)');
  if patched = definition then raise exception 'SLEEP_MINUTES_GRID_ANCHOR_MISSING'; end if;
  definition := patched;

  -- The offset line counts from the instant the band started it.
  patched := replace(definition,
    'select n.sleep_start+(r.offs+m.idx)*interval ''1 minute'' t,r.st::integer st,''offset_line''::text src
  from night n cross join raw_runs r',
    'select n.anchor_start+(r.offs+m.idx)*interval ''1 minute'' t,r.st::integer st,''offset_line''::text src
  from anchored n cross join raw_runs r');
  if patched = definition then raise exception 'SLEEP_MINUTES_OFFSET_ANCHOR_MISSING'; end if;
  definition := patched;

  -- The aggregate fallback spreads one night's totals over its own minutes; a corrected
  -- window must not take minutes it no longer covers.
  patched := replace(definition,
    'from located l cross join night n where not exists(select 1 from valid_staged)',
    'from located l cross join night n where not exists(select 1 from valid_staged)
   and l.t>=n.sleep_start and l.t<n.wake_at');
  if patched = definition then raise exception 'SLEEP_MINUTES_FALLBACK_CLIP_MISSING'; end if;

  execute patched;
end $do$;

-- What the night is worth has to be worth it over the corrected window: the duration and
-- architecture groups are counted from the minutes that window actually holds, not from
-- the totals the band filed for a window that is no longer published.
create or replace function nb.corrected_night_totals(p_user uuid, p_user_day date)
returns table(total_minutes smallint, deep_minutes smallint, light_minutes smallint,
              rem_minutes smallint, wake_count smallint)
language sql stable set search_path='' as $$
  with m as materialized (
    select e.ts,e.stage,e.source src,row_number() over(order by e.ts) rn,
           coalesce(lag(e.stage) over(order by e.ts),4) prev
    from nb.sleep_evidence_minutes(p_user,p_user_day) e
  ), runs as (
    select m.*, sum(case when m.stage=4 and m.prev<>4 then 1 else 0 end) over(order by m.ts) wake_run
    from m
  )
  -- ⚠️ A night whose only evidence is the aggregate fallback has no minute-by-minute
  -- record to re-count: every minute of it comes back as light. Returning nothing is what
  -- makes `correct_sleep_window` refuse such a night rather than flatten its architecture.
  select case when bool_or(src <> 'aggregate_intervals') then count(*) filter(where stage<>4) end::smallint,
         count(*) filter(where stage=0)::smallint,
         count(*) filter(where stage=1)::smallint,
         count(*) filter(where stage=2)::smallint,
         -- A wake is a run of awake minutes with sleep on both sides of it. The last run,
         -- the one that ends the night, is getting up, not waking in the night.
         (select count(distinct r.wake_run) from runs r where r.stage=4
            and exists(select 1 from runs b where b.stage<>4 and b.rn<r.rn)
            and exists(select 1 from runs a where a.stage<>4 and a.rn>r.rn))::smallint
  from runs;
$$;

do $do$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.night_score_parts(uuid,date)'::regprocedure);
  if position('corrected_night_totals' in definition) > 0 then return; end if;

  patched := replace(definition,
    ' select * into n from public.sleep_nights where user_id=p_user and user_day=p_user_day;',
    ' select * into n from public.sleep_nights where user_id=p_user and user_day=p_user_day;
 -- #28 · a corrected night is scored over the window the user asserted.
 if n.corrected_start is not null then
  select t.total_minutes,t.deep_minutes,t.light_minutes,t.wake_count
    into n.total_minutes,n.deep_minutes,n.light_minutes,n.wake_count
  from nb.corrected_night_totals(p_user,p_user_day) t;
  if coalesce(n.total_minutes,0)<=0 then return; end if;
 end if;');
  if patched = definition then raise exception 'NIGHT_SCORE_ROW_ANCHOR_MISSING'; end if;
  definition := patched;

  patched := replace(definition,
    ' rem_min:=case when coalesce(n.sleep_line,'''')='''' then null
   else nullif(nb.sleep_line_minutes(n.sleep_line,2),0) end;',
    ' rem_min:=case when n.corrected_start is not null
     then nullif((select t.rem_minutes from nb.corrected_night_totals(p_user,p_user_day) t),0)
   when coalesce(n.sleep_line,'''')='''' then null
   else nullif(nb.sleep_line_minutes(n.sleep_line,2),0) end;');
  if patched = definition then raise exception 'NIGHT_SCORE_REM_ANCHOR_MISSING'; end if;
  definition := patched;

  -- The page that prints the score must be able to say the night was corrected.
  patched := replace(definition,
    '''duration_basis'',''recorded_segments''',
    '''duration_basis'',case when n.corrected_start is not null then ''user_corrected'' else ''recorded_segments'' end');
  if patched = definition then raise exception 'NIGHT_SCORE_BASIS_ANCHOR_MISSING'; end if;

  execute patched;
end $do$;

-- The row publishes the corrected window, so it must publish the corrected totals too:
-- the phone reads this table directly, and a card saying 8h40m over a window of 7h10m is
-- the same night disagreeing with itself. An AFTER trigger re-counts and writes back; the
-- write re-fires it, finds the totals already right, and stops there.
create or replace function nb.recount_corrected_sleep_night() returns trigger
language plpgsql security definer set search_path='' as $$
declare t record;
begin
  if new.corrected_start is null then return null; end if;
  select * into t from nb.corrected_night_totals(new.user_id,new.user_day);
  if t.total_minutes is null then return null; end if;
  if new.total_minutes is distinct from t.total_minutes
     or new.deep_minutes is distinct from t.deep_minutes
     or new.light_minutes is distinct from t.light_minutes
     or new.wake_count is distinct from t.wake_count then
    update public.sleep_nights set total_minutes=t.total_minutes, deep_minutes=t.deep_minutes,
      light_minutes=t.light_minutes, wake_count=t.wake_count
    where user_id=new.user_id and user_day=new.user_day;
  end if;
  return null;
end $$;

drop trigger if exists sleep_correction_recount on public.sleep_nights;
create trigger sleep_correction_recount
  after insert or update on public.sleep_nights
  for each row execute function nb.recount_corrected_sleep_night();

-- A correction is a request like any other; it gets its own small allowance rather than
-- borrowing the meal endpoint's. The allowance has two halves — the cap in the function
-- and the enum on the table — and both have to learn the name.
alter table nb.request_budgets drop constraint if exists request_budgets_endpoint_check;
alter table nb.request_budgets add constraint request_budgets_endpoint_check
  check (endpoint = any (array['metric-read','meal-commit','meal-operation','turn','archive-data',
    'export','account-delete','meal','asr','sleep-correction']));

do $do$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.consume_request_budget(uuid,text)'::regprocedure);
  if position('sleep-correction' in definition) > 0 then return; end if;
  patched := replace(definition, 'when ''archive-data'' then 6', 'when ''sleep-correction'' then 10 when ''archive-data'' then 6');
  if patched = definition then raise exception 'REQUEST_BUDGET_ANCHOR_MISSING'; end if;
  execute patched;
end $do$;

-- The two entries the product has: the sleep page's save, and a confirmed voice or text
-- request. Both land here, so the rule about what a legal night is has one home.
create or replace function public.correct_sleep_window(p_user_day date, p_start text, p_end text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare owner uuid:=auth.uid(); zone text; budget jsonb;
 v_start timestamptz; v_end timestamptz; v_minutes integer; n public.sleep_nights%rowtype;
begin
 if owner is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if exists(select 1 from public.profiles where user_id=owner and deletion_requested_at is not null)
 then raise exception 'ACCOUNT_DELETING' using errcode='42501'; end if;
 if coalesce((select choice from public.consents where user_id=owner order by decided_at desc,id desc limit 1),'')<>'granted'
 then raise exception 'CONSENT_WITHDRAWN' using errcode='42501'; end if;
 budget:=public.consume_request_budget('sleep-correction');
 if not (budget->>'allowed')::boolean then raise exception 'RATE_LIMITED' using errcode='54000'; end if;
 select coalesce(timezone,'UTC') into zone from public.profiles where user_id=owner;

 -- nb.calculation_clock() is now() on a user request and the replay instant under a
 -- settle, which is also what makes this bound testable against a fixed fixture.
 if p_user_day is null or p_user_day > nb.user_day_of(nb.calculation_clock(),zone)
 then raise exception 'NO_SLEEP_NIGHT' using errcode='22023'; end if;
 -- Replay is chronological, so an old correction would recompute every day after it.
 -- Thirty days is the sleep page's own longest window; past that the night is history.
 if p_user_day < nb.user_day_of(nb.calculation_clock(),zone)-30
 then raise exception 'CORRECTION_TOO_OLD' using errcode='22023'; end if;
 if not nb.sleep_night_is_canonical(owner,p_user_day)
 then raise exception 'NO_SLEEP_NIGHT' using errcode='22023'; end if;

 if coalesce(trim(p_start),'') !~ '^\d{1,2}:\d{2}(:\d{2})?$'
 or coalesce(trim(p_end),'')   !~ '^\d{1,2}:\d{2}(:\d{2})?$'
 then raise exception 'BAD_TIME' using errcode='22023'; end if;
 if trim(p_start)=trim(p_end) then raise exception 'END_BEFORE_START' using errcode='22023'; end if;

 -- Local wall clock, as the user said it. The end belongs to the day the night is filed
 -- under — waking is what dates a night (ADR 0020) — and the start is the most recent
 -- instant of that clock time before it, which is how a night crosses midnight.
 v_end   := (p_user_day::text||' '||trim(p_end))::timestamp at time zone zone;
 v_start := (p_user_day::text||' '||trim(p_start))::timestamp at time zone zone;
 if v_start >= v_end then v_start := v_start - interval '1 day'; end if;

 update public.sleep_nights
    set corrected_start=v_start, corrected_end=v_end, corrected_at=now()
  where user_id=owner and user_day=p_user_day;
 if not found then raise exception 'NO_SLEEP_NIGHT' using errcode='22023'; end if;

 -- The window has to hold sleep the band actually recorded. Raising here rolls the
 -- update back with it: a night is never republished as a window of nothing.
 select count(*) into v_minutes from nb.sleep_evidence_minutes(owner,p_user_day) m;
 if coalesce(v_minutes,0)=0 then raise exception 'WINDOW_HAS_NO_SLEEP' using errcode='22023'; end if;
 -- Minutes, but none of them attributed: nothing here can be re-counted over a new window.
 select t.total_minutes into v_minutes from nb.corrected_night_totals(owner,p_user_day) t;
 if v_minutes is null then raise exception 'NO_STAGE_LINE' using errcode='22023'; end if;
 if v_minutes=0 then raise exception 'WINDOW_HAS_NO_SLEEP' using errcode='22023'; end if;
 if not nb.sleep_night_is_canonical(owner,p_user_day)
 then raise exception 'WAKE_LEAVES_THE_DAY' using errcode='22023'; end if;

 select * into n from public.sleep_nights where user_id=owner and user_day=p_user_day;
 return jsonb_build_object('user_day',p_user_day,'corrected',true,
   'sleep_start',n.sleep_start,'wake_at',n.wake_at,'corrected_at',n.corrected_at,
   'recorded_start',n.raw->>'recorded_start','recorded_end',n.raw->>'recorded_end',
   'total_minutes',v_minutes);
end $$;

create or replace function public.clear_sleep_correction(p_user_day date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare owner uuid:=auth.uid(); budget jsonb; n public.sleep_nights%rowtype;
begin
 if owner is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if coalesce((select choice from public.consents where user_id=owner order by decided_at desc,id desc limit 1),'')<>'granted'
 then raise exception 'CONSENT_WITHDRAWN' using errcode='42501'; end if;
 budget:=public.consume_request_budget('sleep-correction');
 if not (budget->>'allowed')::boolean then raise exception 'RATE_LIMITED' using errcode='54000'; end if;
 update public.sleep_nights set corrected_start=null, corrected_end=null, corrected_at=null
  where user_id=owner and user_day=p_user_day and corrected_start is not null;
 if not found then raise exception 'NO_CORRECTION' using errcode='22023'; end if;
 select * into n from public.sleep_nights where user_id=owner and user_day=p_user_day;
 return jsonb_build_object('user_day',p_user_day,'corrected',false,
   'sleep_start',n.sleep_start,'wake_at',n.wake_at);
end $$;

revoke all on function public.correct_sleep_window(date,text,text) from public,anon;
revoke all on function public.clear_sleep_correction(date) from public,anon;
grant execute on function public.correct_sleep_window(date,text,text) to authenticated,service_role;
grant execute on function public.clear_sleep_correction(date) to authenticated,service_role;
revoke all on function nb.corrected_night_totals(uuid,date), nb.publish_sleep_correction(),
 nb.recount_corrected_sleep_night() from public,anon,authenticated;
