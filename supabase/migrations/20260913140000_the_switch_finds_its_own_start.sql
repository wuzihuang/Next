-- The switch finds its own start.
--
-- The first device walk asked the obvious question: saying which HOOP is on your wrist
-- should be one tap, not a picker and a time wheel. Tapping the other HOOP's card already
-- is the choice — there are only two. And the moment the stretch began is not something
-- the wearer should have to remember: the bands know it. The one you put on has been
-- recording a pulse since you put it on; the one on the charger has not.
--
-- So a declaration with no time is filed at `now` and marked `auto`. The phone then reads
-- the newly worn band — it has to, the link just moved there — and calls
-- `settle_wear_start`, which walks that band's own run of on-wrist ticks backwards and
-- moves the declaration to where the run begins. It only does that while the band worn
-- until then was idle across the same stretch: two wrists lit at once is not something
-- evidence can resolve, so the declaration stays at `now`. A time the wearer pinned by
-- hand is `manual` and is never moved.

alter table public.wear_events drop constraint if exists wear_events_source_check;
alter table public.wear_events add constraint wear_events_source_check
  check (source in ('manual', 'auto', 'bind', 'release'));
comment on column public.wear_events.source is
  'manual · a time the wearer pinned. auto · the app declared at now and let the evidence move the start.';

-- ---------------------------------------------------------------- wrist evidence

-- The ticks one band recorded with a pulse. A band on a charger reports no heart rate, so
-- a pulse is the closest thing to "this was on a wrist" the firmware gives us. Held ticks
-- and canonical ticks both count: which table a tick sits in says who it was filed for,
-- not which band measured it.
create or replace function nb.band_pulse_ticks(
  p_user uuid, p_device_key text, p_from timestamptz, p_to timestamptz
) returns setof timestamptz language sql stable security definer set search_path = '' as $$
  select b.ts from public.band_standby_samples b
    where b.user_id = p_user and b.device_key = p_device_key and b.domain = 'origin'
      and b.ts >= p_from and b.ts <= p_to
      and jsonb_typeof(b.values->'heart') = 'number' and (b.values->>'heart')::numeric > 0
  union
  select r.ts from public.raw_samples r
    where r.user_id = p_user and r.src = 'band' and r.ts >= p_from and r.ts <= p_to
      and coalesce(r.heart, 0) > 0
      and coalesce(r.domain_sources->'origin'->>'device_key', r.ingestion_device_key) = p_device_key;
$$;

-- Where the run of wrist evidence that is live at `p_now` begins, or null when there is
-- no such run — the band is stale, it only just went on, or the other band was on a wrist
-- too and no evidence can say which one the person meant.
create or replace function nb.wear_start_from_evidence(
  p_user uuid, p_device_id uuid, p_now timestamptz, p_floor timestamptz, p_outgoing_key text
) returns timestamptz language plpgsql stable security definer set search_path = '' as $$
declare
  dev public.devices%rowtype; key text; horizon timestamptz;
  gap constant interval := interval '45 minutes';
  tick timestamptz; start_ts timestamptz; prev timestamptz;
  incoming integer; outgoing integer;
begin
  select * into dev from public.devices where id = p_device_id and user_id = p_user and unbound_at is null;
  if not found then return null; end if;
  key := coalesce(dev.client_key, dev.ble_identifier);
  horizon := greatest(dev.bound_at, p_floor, p_now - interval '24 hours');
  if horizon >= p_now then return null; end if;
  -- Walk back from the declaration. `prev` starts at the declaration itself, so a band
  -- whose newest tick is already stale never backdates anything.
  prev := p_now;
  for tick in select t from nb.band_pulse_ticks(p_user, key, horizon, p_now) t order by t desc loop
    if prev - tick <= gap then start_ts := tick; prev := tick; else exit; end if;
  end loop;
  -- A run that started minutes ago is the declaration itself; nothing to move.
  if start_ts is null or start_ts > p_now - interval '10 minutes' then return null; end if;
  if p_outgoing_key is not null and p_outgoing_key <> key then
    select count(*) into outgoing from nb.band_pulse_ticks(p_user, p_outgoing_key, start_ts, p_now) t;
    select count(*) into incoming from nb.band_pulse_ticks(p_user, key, start_ts, p_now) t;
    if outgoing > greatest(2, incoming / 5) then return null; end if;
  end if;
  return start_ts;
end $$;

-- ---------------------------------------------------------------- declarations

-- No time given means "I'm wearing this one" and nothing else: filed at now, marked auto,
-- and left for `settle_wear_start` to move once the band has been read. A time given is
-- the wearer's own correction and is taken exactly as it is.
create or replace function public.record_wear_event(
  p_device_id uuid, p_effective_at timestamptz default now(), p_client_op_id text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid(); dev public.devices%rowtype; existing public.wear_events%rowtype;
  effective timestamptz; previous timestamptz; moved integer := 0; kind text;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  if exists (select 1 from public.profiles where user_id = u and deletion_requested_at is not null)
    then raise exception 'ACCOUNT_DELETING' using errcode = '42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text, 74));
  if p_client_op_id is not null then
    select * into existing from public.wear_events where user_id = u and client_op_id = p_client_op_id;
    if found then
      return public.wear_timeline() || jsonb_build_object('moved', 0,
        'counted_from', existing.effective_at, 'inferred', existing.source = 'auto');
    end if;
  end if;
  select * into dev from public.devices where id = p_device_id and user_id = u and unbound_at is null;
  if not found then raise exception 'DEVICE_NOT_BOUND' using errcode = '42501'; end if;
  kind := case when p_effective_at is null then 'auto' else 'manual' end;
  if kind = 'manual' and (not isfinite(p_effective_at) or p_effective_at > now() + interval '5 minutes') then
    raise exception 'INVALID_EFFECTIVE_AT' using errcode = '22023';
  end if;
  -- A band cannot have been worn for this account before it was bound.
  effective := greatest(coalesce(p_effective_at, now()), dev.bound_at);
  select max(effective_at) into previous from public.wear_events where user_id = u;
  insert into public.wear_events(user_id, device_id, effective_at, source, client_op_id)
    values (u, p_device_id, effective, kind, p_client_op_id);
  moved := nb.reproject_wear(u, least(effective, coalesce(previous, effective)), now());
  return public.wear_timeline() || jsonb_build_object('moved', moved,
    'counted_from', effective, 'inferred', kind = 'auto');
end $$;
revoke all on function public.record_wear_event(uuid, timestamptz, text) from public, anon;
grant execute on function public.record_wear_event(uuid, timestamptz, text) to authenticated;

-- Called once the phone has read the band it just switched to. Moves that declaration back
-- to where the band's own wrist evidence starts, never across an earlier declaration, and
-- never a declaration the wearer pinned.
create or replace function public.settle_wear_start(p_client_op_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid(); ev public.wear_events%rowtype; floor_ts timestamptz;
  outgoing text; start_ts timestamptz; moved integer := 0;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text, 74));
  if p_client_op_id is not null then
    select * into ev from public.wear_events where user_id = u and client_op_id = p_client_op_id;
  else
    select * into ev from public.wear_events where user_id = u
      order by effective_at desc, recorded_at desc limit 1;
  end if;
  if not found or ev.source <> 'auto' then
    return public.wear_timeline() || jsonb_build_object('moved', 0,
      'counted_from', ev.effective_at, 'inferred', coalesce(ev.source, '') = 'auto');
  end if;
  -- An earlier declaration already spoke for the stretch before it; stop there.
  select coalesce(max(effective_at), '-infinity'::timestamptz) into floor_ts
    from public.wear_events where user_id = u
      and (effective_at < ev.effective_at
           or (effective_at = ev.effective_at and recorded_at < ev.recorded_at));
  outgoing := nb.wearer_device_key(u, ev.effective_at - interval '1 second');
  start_ts := nb.wear_start_from_evidence(u, ev.device_id, ev.effective_at, floor_ts, outgoing);
  if start_ts is null or start_ts >= ev.effective_at then
    return public.wear_timeline() || jsonb_build_object('moved', 0,
      'counted_from', ev.effective_at, 'inferred', true);
  end if;
  update public.wear_events set effective_at = start_ts where id = ev.id;
  moved := nb.reproject_wear(u, start_ts, now());
  return public.wear_timeline() || jsonb_build_object('moved', moved,
    'counted_from', start_ts, 'inferred', true);
end $$;
revoke all on function public.settle_wear_start(text) from public, anon;
grant execute on function public.settle_wear_start(text) to authenticated;
