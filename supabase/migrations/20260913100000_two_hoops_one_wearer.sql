-- Two HOOPs, one wearer (docs/plans/2026-09-12-dual-device-continuity.md §04.5).
--
-- The first version of dual-device continuity is deliberately narrow: an account owns at
-- most two bands, each in a fixed slot (A / B), and the person declares which one is on
-- the wrist. That declaration is the only source-selection rule. Every band still uploads
-- everything it recorded; a sample from the band that was not declared worn at its
-- timestamp lands in `band_standby_samples` instead of the canonical health tables, and a
-- later declaration (`I switched at 08:00`) moves rows between the two.
--
-- Nothing here changes how a single-band account ingests: with one bound device and no
-- wear events, `nb.wearer_device_key` returns that device and the wrapper below calls the
-- original ingest unchanged.

-- ---------------------------------------------------------------- devices: slots

alter table public.devices add column if not exists slot text
  check (slot in ('A', 'B'));
comment on column public.devices.slot is
  'Fixed position in the account''s device set. Given at activation, never changes with wearing, preference or a new BLE alias. UI names the band HOOP A / HOOP B by it.';

update public.devices set slot = 'A' where slot is null and unbound_at is null;

drop index if exists public.devices_one_bound_per_user;
create unique index devices_one_bound_per_slot
  on public.devices (user_id, slot) where unbound_at is null;

-- Old clients insert without a slot. The first bound band is A; the second is B.
create or replace function nb.devices_default_slot() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.slot is null and new.unbound_at is null then
    if not exists (select 1 from public.devices
                   where user_id = new.user_id and slot = 'A' and unbound_at is null) then
      new.slot := 'A';
    elsif not exists (select 1 from public.devices
                      where user_id = new.user_id and slot = 'B' and unbound_at is null) then
      new.slot := 'B';
    else
      raise exception 'DEVICE_SET_FULL' using errcode = '23505';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists devices_default_slot on public.devices;
create trigger devices_default_slot before insert on public.devices
  for each row execute function nb.devices_default_slot();

-- ---------------------------------------------------------------- wear events

create table public.wear_events (
  id            uuid primary key default extensions.gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  device_id     uuid not null references public.devices (id) on delete cascade,
  -- When the person says the switch happened. May be earlier than recorded_at.
  effective_at  timestamptz not null,
  recorded_at   timestamptz not null default now(),
  source        text not null default 'manual' check (source in ('manual', 'bind', 'release')),
  client_op_id  text,
  unique (user_id, client_op_id)
);
create index wear_events_user_effective_idx on public.wear_events (user_id, effective_at desc, recorded_at desc);
alter table public.wear_events enable row level security;
create policy wear_events_select on public.wear_events
  for select to authenticated using ((select auth.uid()) = user_id);
-- No insert/update/delete policy: declarations go through record_wear_event().
comment on table public.wear_events is
  'Each row starts a wear segment for one device until the next row. Segments never overlap: a person wears one HOOP at a time.';

-- ---------------------------------------------------------------- standby observations

create table public.band_standby_samples (
  user_id         uuid not null references auth.users (id) on delete cascade,
  device_key      text not null,
  domain          text not null check (domain in ('origin', 'hrv', 'temperature', 'oxygen', 'response')),
  ts              timestamptz not null,
  sampled_tz      text not null,
  mapping_version text,
  observed_at     timestamptz,
  values          jsonb not null,
  received_at     timestamptz not null default now(),
  primary key (user_id, device_key, domain, ts)
);
create index band_standby_samples_user_ts_idx on public.band_standby_samples (user_id, ts);
alter table public.band_standby_samples enable row level security;
create policy band_standby_samples_select on public.band_standby_samples
  for select to authenticated using ((select auth.uid()) = user_id);
comment on table public.band_standby_samples is
  'Samples a band recorded while the person had declared the other HOOP worn. Kept per device so a later declaration can promote them without reading the band again.';

alter table public.sleep_nights add column if not exists device_key text;
create table public.band_standby_sleep (
  user_id     uuid not null references auth.users (id) on delete cascade,
  device_key  text not null,
  user_day    date not null,
  row         jsonb not null,
  received_at timestamptz not null default now(),
  primary key (user_id, device_key, user_day)
);
alter table public.band_standby_sleep enable row level security;
create policy band_standby_sleep_select on public.band_standby_sleep
  for select to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------- who was wearing what

-- The device declared worn at `p_at`. Without any declaration the only bound band (or slot
-- A when both exist) counts as worn since it was bound, so single-band accounts and the
-- first days after activating B behave exactly as before.
create or replace function nb.wearer_device_key(p_user uuid, p_at timestamptz) returns text
language sql stable security definer set search_path = '' as $$
  -- A declaration names a band that was bound at that moment; after Release both,
  -- nobody is worn and the single-band paths take over again.
  select coalesce(
    (select d.ble_identifier from public.wear_events w
       join public.devices d on d.id = w.device_id
      where w.user_id = p_user and w.effective_at <= p_at
        and d.bound_at <= p_at and (d.unbound_at is null or d.unbound_at > p_at)
      order by w.effective_at desc, w.recorded_at desc limit 1),
    (select d.ble_identifier from public.devices d
      where d.user_id = p_user and d.bound_at <= p_at
        and (d.unbound_at is null or d.unbound_at > p_at)
      order by d.slot nulls last, d.bound_at limit 1));
$$;

-- ---------------------------------------------------------------- ingest: standby stash

alter function public.ingest_band_domain(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz)
  rename to ingest_band_domain_single;

create function public.ingest_band_domain(
  p_device_key text, p_domain text, p_day date, p_timezone text,
  p_start timestamptz, p_end timestamptz, p_samples jsonb,
  p_status text default 'complete', p_mapping_version text default 'veepoo-rmssd-v1',
  p_observed_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid(); s jsonb; t timestamptz; w text;
  worn jsonb := '[]'; standby_inserted integer := 0; standby_unchanged integer := 0; n integer;
  fields text[]; old public.raw_samples%rowtype; owner text; held jsonb; result jsonb;
begin
  -- Sleep never comes through here; RR evidence is already keyed per device.
  if u is null or p_domain in ('sleep', 'rr') or p_samples is null or jsonb_typeof(p_samples) <> 'array'
     or not exists (select 1 from public.devices where user_id = u and unbound_at is null and slot = 'B') then
    return public.ingest_band_domain_single(p_device_key, p_domain, p_day, p_timezone, p_start, p_end,
      p_samples, p_status, p_mapping_version, p_observed_at);
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text, 74));
  fields := case p_domain when 'origin' then array['heart','step','cal','dis','met','stress','sleep_states']
    when 'hrv' then array['hrv'] when 'temperature' then array['temp']
    when 'oxygen' then array['spo2'] else array['optical'] end;
  for s in select value from jsonb_array_elements(p_samples) loop
    begin
      t := case when jsonb_typeof(s) = 'object' then (s->>'ts')::timestamptz end;
    exception when others then t := null; end;
    -- Anything malformed goes to the original ingest, which rejects it the usual way.
    if t is null then worn := worn || s; continue; end if;
    w := nb.wearer_device_key(u, t);
    if w is null or w = p_device_key then
      worn := worn || s;
      -- The wearer takes the tick. Whatever the other band filed there moves aside so
      -- the original ingest (which refuses a second device) can accept this one.
      if p_domain in ('origin', 'hrv', 'temperature') then
        select * into old from public.raw_samples where user_id = u and ts = t and src = 'band' for update;
        if found then
          owner := coalesce(old.domain_sources->p_domain->>'device_key', old.ingestion_device_key);
          if owner is not null and owner <> p_device_key then
            held := jsonb_strip_nulls((select jsonb_object_agg(f, to_jsonb(old)->f) from unnest(fields) f));
            if held <> '{}'::jsonb then
              insert into public.band_standby_samples(user_id, device_key, domain, ts, sampled_tz, mapping_version, observed_at, values)
                values (u, owner, p_domain, t, old.sampled_tz, old.domain_sources->p_domain->>'mapping_version',
                  coalesce((old.domain_sources->p_domain->>'read_at')::timestamptz,
                           (old.domain_sources->p_domain->>'observed_at')::timestamptz),
                  held || jsonb_build_object('domain_meta', old.domain_sources->p_domain))
                on conflict (user_id, device_key, domain, ts) do update
                  set values = excluded.values, observed_at = excluded.observed_at, received_at = now();
            end if;
            update public.raw_samples set
              heart = case when p_domain = 'origin' then null else heart end,
              step = case when p_domain = 'origin' then null else step end,
              cal = case when p_domain = 'origin' then null else cal end,
              dis = case when p_domain = 'origin' then null else dis end,
              met = case when p_domain = 'origin' then null else met end,
              stress = case when p_domain = 'origin' then null else stress end,
              sleep_states = case when p_domain = 'origin' then null else sleep_states end,
              hrv = case when p_domain = 'hrv' then null else hrv end,
              temp = case when p_domain = 'temperature' then null else temp end,
              domain_sources = old.domain_sources - p_domain,
              ingestion_device_key = case when old.ingestion_device_key = owner then p_device_key else old.ingestion_device_key end
              where user_id = u and ts = t and src = 'band';
          end if;
        end if;
      elsif p_domain = 'oxygen' then
        delete from public.oxygen_samples where user_id = u and ts = t and src = 'band'
          and exists (select 1 from public.band_standby_samples b where b.user_id = u and b.domain = 'oxygen' and b.ts = t and b.device_key <> p_device_key);
      elsif p_domain = 'response' then
        delete from public.response_samples where user_id = u and ts = t and src = 'band'
          and exists (select 1 from public.band_standby_samples b where b.user_id = u and b.domain = 'response' and b.ts = t and b.device_key <> p_device_key);
      end if;
    else
      held := jsonb_strip_nulls((select jsonb_object_agg(f, s->f) from unnest(fields) f where s ? f));
      if held = '{}'::jsonb then worn := worn || s; continue; end if;  -- let the original reject it
      insert into public.band_standby_samples(user_id, device_key, domain, ts, sampled_tz, mapping_version, observed_at, values)
        values (u, p_device_key, p_domain, t, p_timezone, p_mapping_version,
          coalesce((s->>'origin_read_at')::timestamptz, p_observed_at), held)
        on conflict (user_id, device_key, domain, ts) do update
          set values = excluded.values, observed_at = excluded.observed_at, mapping_version = excluded.mapping_version, received_at = now()
          where band_standby_samples.values is distinct from excluded.values
             or band_standby_samples.observed_at is distinct from excluded.observed_at;
      get diagnostics n = row_count;
      if n = 1 then standby_inserted := standby_inserted + 1; else standby_unchanged := standby_unchanged + 1; end if;
    end if;
  end loop;
  result := public.ingest_band_domain_single(p_device_key, p_domain, p_day, p_timezone, p_start, p_end,
    worn, p_status, p_mapping_version, p_observed_at);
  return result || jsonb_build_object(
    'inserted', (result->>'inserted')::integer + standby_inserted,
    'unchanged', (result->>'unchanged')::integer + standby_unchanged,
    'standby', standby_inserted + standby_unchanged);
end $$;
revoke all on function public.ingest_band_domain(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz) from public, anon;
grant execute on function public.ingest_band_domain(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz) to authenticated;
revoke all on function public.ingest_band_domain_single(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz) from public, anon, authenticated;

-- Sleep is upserted straight into sleep_nights by the phone. A night filed by the band
-- that was not worn at wake time is held aside; the wearer's night wins.
create or replace function nb.sleep_nights_wearer_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
declare w text; at timestamptz; tz text;
begin
  if new.device_key is null then return new; end if;
  select timezone into tz from public.profiles where user_id = new.user_id;
  at := coalesce(new.wake_at, (new.user_day::timestamp + interval '12 hours') at time zone coalesce(tz, 'UTC'));
  w := nb.wearer_device_key(new.user_id, at);
  if w is null or w = new.device_key then return new; end if;
  insert into public.band_standby_sleep(user_id, device_key, user_day, row)
    values (new.user_id, new.device_key, new.user_day, to_jsonb(new) - 'user_id' - 'device_key')
    on conflict (user_id, device_key, user_day) do update set row = excluded.row, received_at = now();
  return null;
end $$;
drop trigger if exists sleep_nights_wearer_guard on public.sleep_nights;
create trigger sleep_nights_wearer_guard before insert or update on public.sleep_nights
  for each row execute function nb.sleep_nights_wearer_guard();

-- The phone publishes a night through here so the answer is the same shape whether the
-- night was filed (the wearer's) or held (the other band's). The direct upsert stays for
-- older clients; the trigger above guards it.
create or replace function public.publish_sleep_night(p_row jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid(); night public.sleep_nights; w text; at timestamptz; tz text; saved public.sleep_nights;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  if (select choice from public.consents where user_id = u order by decided_at desc limit 1) is distinct from 'granted'
    then raise exception 'CONSENT_REQUIRED' using errcode = '42501'; end if;
  if p_row is null or jsonb_typeof(p_row) <> 'object' or (p_row ? 'user_id' and p_row->>'user_id' is distinct from u::text)
    then raise exception 'INVALID_SLEEP_ROW' using errcode = '22023'; end if;
  night := jsonb_populate_record(null::public.sleep_nights, p_row || jsonb_build_object('user_id', u));
  night.raw := coalesce(night.raw, '{}'::jsonb);
  if night.user_day is null then raise exception 'INVALID_SLEEP_ROW' using errcode = '22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text, 74));
  if night.device_key is not null then
    select timezone into tz from public.profiles where user_id = u;
    at := coalesce(night.wake_at, (night.user_day::timestamp + interval '12 hours') at time zone coalesce(tz, 'UTC'));
    w := nb.wearer_device_key(u, at);
    if w is not null and w <> night.device_key then
      insert into public.band_standby_sleep(user_id, device_key, user_day, row)
        values (u, night.device_key, night.user_day, to_jsonb(night) - 'user_id' - 'device_key')
        on conflict (user_id, device_key, user_day) do update set row = excluded.row, received_at = now();
      return jsonb_build_array(to_jsonb(night) || jsonb_build_object('held', true));
    end if;
  end if;
  -- Same merge the phone's upsert relied on: the row is the band's newest filing.
  insert into public.sleep_nights select (night).*
    on conflict (user_id, user_day) do update set
      total_minutes = excluded.total_minutes, deep_minutes = excluded.deep_minutes,
      light_minutes = excluded.light_minutes, wake_count = excluded.wake_count,
      raw = excluded.raw, sleep_line = excluded.sleep_line, device_key = excluded.device_key,
      sleep_start = excluded.sleep_start, wake_at = excluded.wake_at
    returning * into saved;
  return jsonb_build_array(to_jsonb(saved));
end $$;
revoke all on function public.publish_sleep_night(jsonb) from public, anon;
grant execute on function public.publish_sleep_night(jsonb) to authenticated;

-- ---------------------------------------------------------------- re-projection

-- After a declaration changes who wore what in [p_from, p_to], swap held and canonical
-- values so every tick again belongs to the band declared worn. Days touched are marked
-- dirty for settlement.
create or replace function nb.reproject_wear(p_user uuid, p_from timestamptz, p_to timestamptz) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  r record; w text; owner text; fields text[]; held jsonb; promoted jsonb; moved integer := 0;
  tz text; d date; days date[] := '{}'; standby public.band_standby_samples%rowtype;
  night record; held_night public.band_standby_sleep%rowtype;
begin
  select timezone into tz from public.profiles where user_id = p_user;
  tz := coalesce(tz, 'UTC');
  for r in
    select ts, domain from (
      select ts, domain from public.band_standby_samples where user_id = p_user and ts >= p_from and ts <= p_to
      union
      select ts, d.domain from public.raw_samples, (values ('origin'),('hrv'),('temperature')) d(domain)
        where user_id = p_user and src = 'band' and ts >= p_from and ts <= p_to
    ) x order by ts
  loop
    w := nb.wearer_device_key(p_user, r.ts);
    if w is null then continue; end if;
    if r.domain in ('origin', 'hrv', 'temperature') then
      fields := case r.domain when 'origin' then array['heart','step','cal','dis','met','stress','sleep_states']
        when 'hrv' then array['hrv'] else array['temp'] end;
      select coalesce(domain_sources->r.domain->>'device_key', ingestion_device_key) into owner
        from public.raw_samples where user_id = p_user and ts = r.ts and src = 'band';
      if owner = w then continue; end if;
      select * into standby from public.band_standby_samples
        where user_id = p_user and device_key = w and domain = r.domain and ts = r.ts;
      if not found then continue; end if;
      -- Hold what the current owner has there, then write the wearer's values.
      if owner is not null then
        select jsonb_strip_nulls((select jsonb_object_agg(f, to_jsonb(s)->f) from unnest(fields) f)) into held
          from public.raw_samples s where user_id = p_user and ts = r.ts and src = 'band';
        if held <> '{}'::jsonb then
          insert into public.band_standby_samples(user_id, device_key, domain, ts, sampled_tz, mapping_version, observed_at, values)
            select p_user, owner, r.domain, r.ts, s.sampled_tz, s.domain_sources->r.domain->>'mapping_version',
              coalesce((s.domain_sources->r.domain->>'read_at')::timestamptz, (s.domain_sources->r.domain->>'observed_at')::timestamptz),
              held || jsonb_build_object('domain_meta', s.domain_sources->r.domain)
            from public.raw_samples s where user_id = p_user and ts = r.ts and src = 'band'
            on conflict (user_id, device_key, domain, ts) do update set values = excluded.values, observed_at = excluded.observed_at, received_at = now();
        end if;
      end if;
      promoted := standby.values - 'domain_meta';
      if exists (select 1 from public.raw_samples where user_id = p_user and ts = r.ts and src = 'band') then
        update public.raw_samples set
          heart = case when r.domain = 'origin' then (promoted->>'heart')::smallint else heart end,
          step = case when r.domain = 'origin' then (promoted->>'step')::integer else step end,
          cal = case when r.domain = 'origin' then (promoted->>'cal')::integer else cal end,
          dis = case when r.domain = 'origin' then (promoted->>'dis')::integer else dis end,
          met = case when r.domain = 'origin' then (promoted->>'met')::numeric else met end,
          stress = case when r.domain = 'origin' then (promoted->>'stress')::smallint else stress end,
          sleep_states = case when r.domain = 'origin' then (promoted->>'sleep_states')::smallint else sleep_states end,
          hrv = case when r.domain = 'hrv' then (promoted->>'hrv')::numeric else hrv end,
          temp = case when r.domain = 'temperature' then (promoted->>'temp')::numeric else temp end,
          domain_sources = (domain_sources - r.domain) || jsonb_build_object(r.domain,
            coalesce(standby.values->'domain_meta', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
              'device_key', w, 'mapping_version', standby.mapping_version, 'read_at', standby.observed_at, 'received_at', now()))),
          ingestion_device_key = case when ingestion_device_key = owner or ingestion_device_key is null then w else ingestion_device_key end
          where user_id = p_user and ts = r.ts and src = 'band';
      else
        insert into public.raw_samples(user_id, ts, src, sampled_tz, heart, step, cal, dis, met, temp, hrv, stress, sleep_states,
            ingestion_device_key, mapping_version, domain_sources)
          values (p_user, r.ts, 'band', standby.sampled_tz,
            (promoted->>'heart')::smallint, (promoted->>'step')::integer, (promoted->>'cal')::integer, (promoted->>'dis')::integer,
            (promoted->>'met')::numeric, (promoted->>'temp')::numeric, (promoted->>'hrv')::numeric,
            (promoted->>'stress')::smallint, (promoted->>'sleep_states')::smallint, w, standby.mapping_version,
            jsonb_build_object(r.domain, coalesce(standby.values->'domain_meta', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
              'device_key', w, 'mapping_version', standby.mapping_version, 'read_at', standby.observed_at, 'received_at', now()))));
      end if;
      delete from public.band_standby_samples where user_id = p_user and device_key = w and domain = r.domain and ts = r.ts;
      moved := moved + 1;
      days := array_append(days, nb.user_day_of(r.ts, tz));
    elsif r.domain = 'oxygen' then
      select * into standby from public.band_standby_samples where user_id = p_user and device_key = w and domain = 'oxygen' and ts = r.ts;
      if found then
        delete from public.oxygen_samples where user_id = p_user and ts = r.ts and src = 'band';
        insert into public.oxygen_samples(user_id, ts, spo2, sampled_tz, src)
          values (p_user, r.ts, (standby.values->>'spo2')::smallint, standby.sampled_tz, 'band') on conflict do nothing;
        delete from public.band_standby_samples where user_id = p_user and device_key = w and domain = 'oxygen' and ts = r.ts;
        moved := moved + 1; days := array_append(days, nb.user_day_of(r.ts, tz));
      end if;
    elsif r.domain = 'response' then
      select * into standby from public.band_standby_samples where user_id = p_user and device_key = w and domain = 'response' and ts = r.ts;
      if found then
        delete from public.response_samples where user_id = p_user and ts = r.ts and src = 'band';
        insert into public.response_samples(user_id, ts, optical, sampled_tz, src)
          values (p_user, r.ts, (standby.values->>'optical')::double precision, standby.sampled_tz, 'band') on conflict do nothing;
        delete from public.band_standby_samples where user_id = p_user and device_key = w and domain = 'response' and ts = r.ts;
        moved := moved + 1; days := array_append(days, nb.user_day_of(r.ts, tz));
      end if;
    end if;
  end loop;
  -- Nights: the wearer at wake time owns the night.
  for night in select user_day, device_key, wake_at from public.sleep_nights
      where user_id = p_user and user_day between nb.user_day_of(p_from, tz) - 1 and nb.user_day_of(p_to, tz) + 1
  loop
    w := nb.wearer_device_key(p_user, coalesce(night.wake_at, (night.user_day::timestamp + interval '12 hours') at time zone tz));
    if w is null or night.device_key is null or night.device_key = w then continue; end if;
    select * into held_night from public.band_standby_sleep where user_id = p_user and device_key = w and user_day = night.user_day;
    if not found then continue; end if;
    insert into public.band_standby_sleep(user_id, device_key, user_day, row)
      select p_user, device_key, user_day, to_jsonb(s) - 'user_id' - 'device_key' from public.sleep_nights s
        where user_id = p_user and user_day = night.user_day
      on conflict (user_id, device_key, user_day) do update set row = excluded.row, received_at = now();
    delete from public.sleep_nights where user_id = p_user and user_day = night.user_day;
    insert into public.sleep_nights
      select (x).* from jsonb_populate_record(null::public.sleep_nights,
        held_night.row || jsonb_build_object('user_id', p_user, 'device_key', w)) x;
    delete from public.band_standby_sleep where user_id = p_user and device_key = w and user_day = night.user_day;
    moved := moved + 1; days := array_append(days, night.user_day);
  end loop;
  days := (select coalesce(array_agg(distinct x), '{}'::date[]) from unnest(days) x);
  foreach d in array days loop
    perform nb.invalidate_calculation(p_user, d);
  end loop;
  return moved;
end $$;

-- ---------------------------------------------------------------- declarations

create or replace function public.record_wear_event(
  p_device_id uuid, p_effective_at timestamptz default now(), p_client_op_id text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid(); dev public.devices%rowtype; existing public.wear_events%rowtype;
  effective timestamptz; previous timestamptz; moved integer := 0;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  if exists (select 1 from public.profiles where user_id = u and deletion_requested_at is not null)
    then raise exception 'ACCOUNT_DELETING' using errcode = '42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text, 74));
  if p_client_op_id is not null then
    select * into existing from public.wear_events where user_id = u and client_op_id = p_client_op_id;
    if found then return public.wear_timeline(); end if;
  end if;
  select * into dev from public.devices where id = p_device_id and user_id = u and unbound_at is null;
  if not found then raise exception 'DEVICE_NOT_BOUND' using errcode = '42501'; end if;
  if p_effective_at is null or not isfinite(p_effective_at) or p_effective_at > now() + interval '5 minutes' then
    raise exception 'INVALID_EFFECTIVE_AT' using errcode = '22023';
  end if;
  -- A band cannot have been worn for this account before it was bound.
  effective := greatest(p_effective_at, dev.bound_at);
  select max(effective_at) into previous from public.wear_events where user_id = u;
  insert into public.wear_events(user_id, device_id, effective_at, source, client_op_id)
    values (u, p_device_id, effective, 'manual', p_client_op_id);
  moved := nb.reproject_wear(u, least(effective, coalesce(previous, effective)), now());
  return public.wear_timeline() || jsonb_build_object('moved', moved);
end $$;
revoke all on function public.record_wear_event(uuid, timestamptz, text) from public, anon;
grant execute on function public.record_wear_event(uuid, timestamptz, text) to authenticated;

create or replace function public.wear_timeline() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'events', coalesce((select jsonb_agg(jsonb_build_object(
        'id', w.id, 'device_id', w.device_id, 'slot', d.slot, 'device_key', d.ble_identifier,
        'effective_at', w.effective_at, 'recorded_at', w.recorded_at, 'source', w.source)
        order by w.effective_at desc, w.recorded_at desc)
      from public.wear_events w join public.devices d on d.id = w.device_id
      where w.user_id = auth.uid()), '[]'::jsonb),
    'wearing', (select jsonb_build_object('device_key', nb.wearer_device_key(auth.uid(), now()))),
    'devices', coalesce((select jsonb_agg(jsonb_build_object(
        'id', d.id, 'slot', d.slot, 'device_key', d.ble_identifier, 'device_number', d.device_number,
        'firmware_version', d.firmware_version, 'battery_percent', d.battery_percent,
        'battery_level', d.battery_level, 'battery_is_percent', d.battery_is_percent,
        'bound_at', d.bound_at, 'last_origin_sync_at', d.last_origin_sync_at,
        'standby_samples', (select count(*) from public.band_standby_samples b
                             where b.user_id = d.user_id and b.device_key = d.ble_identifier))
        order by d.slot)
      from public.devices d where d.user_id = auth.uid() and d.unbound_at is null), '[]'::jsonb));
$$;
revoke all on function public.wear_timeline() from public, anon;
grant execute on function public.wear_timeline() to authenticated;

-- Releasing the set closes both bindings together. History stays; the wear segments end
-- with a release marker so a re-claim starts fresh.
create or replace function public.release_device_set() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); n integer;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text, 74));
  update public.devices set unbound_at = now() where user_id = u and unbound_at is null;
  get diagnostics n = row_count;
  return jsonb_build_object('released', n);
end $$;
revoke all on function public.release_device_set() from public, anon;
grant execute on function public.release_device_set() to authenticated;
