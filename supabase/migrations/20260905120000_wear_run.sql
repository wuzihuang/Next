-- ADR 0010 · worn day and wear run on daily_results.
--
-- A worn day is wrist evidence in at least half of the elapsed five-minute slots of the
-- user day. Coverage that only counts raw rows would light a band charging on the nightstand.
-- Wear run and wear miss are derived from the previous calendar day, not from "the last row
-- that exists", so a missing yesterday breaks the run instead of skipping it.

alter table public.daily_results
  add column if not exists worn boolean not null default false,
  add column if not exists wear_run smallint not null default 0,
  add column if not exists wear_miss smallint not null default 2;

alter table public.daily_results
  drop constraint if exists daily_results_wear_run_check,
  drop constraint if exists daily_results_wear_miss_check;

alter table public.daily_results
  add constraint daily_results_wear_run_check check (wear_run >= 0),
  add constraint daily_results_wear_miss_check check (wear_miss in (0, 1, 2));

comment on column public.daily_results.worn is
  'True when wrist-evidence five-minute slots cover at least half of the elapsed slots.';
comment on column public.daily_results.wear_run is
  'Consecutive worn days ending on this user day. Zero when this day is not worn.';
comment on column public.daily_results.wear_miss is
  '0 while the run is live, 1 the first closed miss, 2 once it has cooled.';

create or replace function nb.compute_worn(p_user uuid, p_user_day date)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz text;
  v_lo timestamptz;
  v_hi timestamptz;
  v_elapsed integer;
  v_worn integer;
begin
  select timezone into v_tz
  from public.profiles
  where user_id = p_user and deletion_requested_at is null;
  if v_tz is null then return false; end if;
  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);
  v_elapsed := least(288, floor(extract(epoch from (least(now(), v_hi) - v_lo)) / 300)::int);
  if v_elapsed <= 0 then return false; end if;
  select count(*)::int into v_worn
  from (
    select 1
    from public.raw_samples s
    where s.user_id = p_user
      and s.ts >= v_lo
      and s.ts < least(now(), v_hi)
      and (s.heart is not null
           or s.stress is not null
           or s.hrv is not null
           or coalesce(s.step, 0) > 0
           or coalesce(s.met, 0) > 1.05)
      and floor(extract(epoch from (s.ts - v_lo)) / 300)::int >= 0
      and floor(extract(epoch from (s.ts - v_lo)) / 300)::int < v_elapsed
    group by floor(extract(epoch from (s.ts - v_lo)) / 300)::int
  ) bins;
  return coalesce(v_worn, 0) * 2 >= v_elapsed;
end;
$$;

create or replace function nb.fill_wear()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  prev_worn boolean;
  prev_run smallint;
  prev_miss smallint;
  v_worn boolean;
begin
  v_worn := nb.compute_worn(new.user_id, new.user_day);
  new.worn := v_worn;
  select r.worn, r.wear_run, r.wear_miss
    into prev_worn, prev_run, prev_miss
  from public.daily_results r
  where r.user_id = new.user_id and r.user_day = new.user_day - 1;
  if not found then
    if v_worn then
      new.wear_run := 1;
      new.wear_miss := 0;
    else
      new.wear_run := 0;
      new.wear_miss := 2;
    end if;
    return new;
  end if;
  if v_worn then
    new.wear_run := case when prev_worn then prev_run + 1 else 1 end;
    new.wear_miss := 0;
  else
    new.wear_run := 0;
    new.wear_miss := case when prev_worn then 1 else least(2, coalesce(prev_miss, 2) + 1) end;
  end if;
  return new;
end;
$$;

drop trigger if exists daily_results_wear on public.daily_results;
create trigger daily_results_wear
before insert or update on public.daily_results
for each row execute function nb.fill_wear();

revoke execute on function nb.compute_worn(uuid, date) from public, anon, authenticated;
revoke execute on function nb.fill_wear() from public, anon, authenticated;

-- Oldest day first so yesterday's run is already sitting on the previous row.
do $$
declare
  r record;
begin
  for r in
    select user_id, user_day
    from public.daily_results
    order by user_id, user_day
  loop
    update public.daily_results
    set worn = worn
    where user_id = r.user_id and user_day = r.user_day;
  end loop;
end;
$$;
