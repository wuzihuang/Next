-- Temperature is read from the SDK's health-history command, separately from the origin
-- row that owns its timestamp. If that auxiliary read fails once, the origin row can reach
-- raw_samples without temp and the sync watermark can move past it. Later syncs must be able
-- to complete that row without opening a general update path on collected measurements.

create or replace function public.fill_temp(p_samples jsonb)
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
    select s.ts, s.temp
    from jsonb_to_recordset(p_samples) as s(ts timestamptz, temp numeric)
    where s.ts is not null
      and s.temp between 20 and 45
  )
  update public.raw_samples r
     set temp = i.temp
    from incoming i
   where r.user_id = v_user
     and r.ts = i.ts
     and r.temp is null;

  get diagnostics v_n = row_count;
  return jsonb_build_object('filled', v_n);
end;
$$;

revoke execute on function public.fill_temp(jsonb) from public, anon;
grant execute on function public.fill_temp(jsonb) to authenticated;
