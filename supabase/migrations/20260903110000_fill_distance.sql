-- Origin-data disValue is kilometres. The app used to Int() that figure, so every
-- five-minute slot stored 0 m and daily_training.distance_m summed to 0. Mapping now
-- converts km → m, but raw_samples is insert-only and the sync watermark never
-- resends a tick: those zeros would otherwise stay zeros.
--
-- Same narrow door as fill_hrv (20260903100000): authenticated, own rows, only where
-- the stored value is still empty (null or the truncated zero). A real metre count
-- already on the row is left alone.

create or replace function public.fill_dis(p_samples jsonb)
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
  if jsonb_array_length(p_samples) > 5000 then
    raise exception 'TOO MANY SAMPLES' using errcode = '22023';
  end if;

  with incoming as (
    select s.ts, s.dis
    from jsonb_to_recordset(p_samples) as s(ts timestamptz, dis integer)
    where s.ts is not null and s.dis is not null and s.dis > 0
  )
  update public.raw_samples r
     set dis = i.dis
    from incoming i
   where r.user_id = v_user
     and r.ts = i.ts
     and (r.dis is null or r.dis = 0);

  get diagnostics v_n = row_count;
  return jsonb_build_object('filled', v_n);
end;
$$;

revoke execute on function public.fill_dis(jsonb) from public, anon;
grant execute on function public.fill_dis(jsonb) to authenticated;
