-- The band's HRV all day long, one value per five-minute tick.
--
-- The HOOP measures HRV every ten minutes around the clock, not only at night: a sync on
-- 2026-09-03 read 119 measured minutes spread over every hour of the day. Only one number
-- ever reached the server — night_hrv's single nightly median — so a full day of readings
-- was thrown away at the bridge. This column keeps them.
--
-- ⚠️ RMSSD in milliseconds, computed from the vendor's RR intervals, never the vendor's own
-- opaque hrv scalar. Same rule as night_hrv.rmssd_ms: that scalar is diagnostics, and a
-- column that says ms holds ms.

alter table public.raw_samples
  add column if not exists hrv numeric(5, 1);

comment on column public.raw_samples.hrv is
  'RMSSD in ms for this tick, from the band''s RR intervals. Never the vendor hrv scalar.';

-- ---------------------------------------------------------------- filling in what was late

-- raw_samples is insert-only by policy (20260901120100_rls) and a stored tick is never
-- rewritten. HRV, though, is a separate SDK history domain read by its own command, and it
-- can land a sync after the tick it belongs to — the tick is already stored, so there is no
-- insert left to carry the value. This is the one narrow door: it fills nulls and can do
-- nothing else. A value already stored is left exactly as it is, so the insert-only promise
-- still holds for every number the table has.
--
-- No src filter: every row in this table is the band's, and src is on its way out
-- (F7 rule 09 · migration 20260902020000).

create or replace function public.fill_hrv(p_samples jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_n    integer;
begin
  if v_user is null then
    raise exception 'UNAUTHENTICATED' using errcode = '28000';
  end if;
  if p_samples is null or jsonb_typeof(p_samples) <> 'array' then
    return jsonb_build_object('filled', 0);
  end if;
  -- A day is 288 ticks; a week's backfill is under 2016. Anything past that is not a sync.
  if jsonb_array_length(p_samples) > 5000 then
    raise exception 'TOO MANY SAMPLES' using errcode = '22023';
  end if;

  with incoming as (
    select s.ts, s.hrv
    from jsonb_to_recordset(p_samples) as s(ts timestamptz, hrv numeric)
    where s.ts is not null and s.hrv is not null
  )
  update public.raw_samples r
     set hrv = i.hrv
    from incoming i
   where r.user_id = v_user
     and r.ts = i.ts
     and r.hrv is null;

  get diagnostics v_n = row_count;
  -- jsonb, not a bare integer: a scalar body is not JSON the app's decoder accepts.
  return jsonb_build_object('filled', v_n);
end;
$$;

revoke execute on function public.fill_hrv(jsonb) from public, anon;
grant execute on function public.fill_hrv(jsonb) to authenticated;
