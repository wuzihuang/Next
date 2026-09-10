-- ADR 0022 · the advice face's turn keeps running after the phone disconnects, with a
-- 110 s model budget. The 90 s execution lease from 20260904092439 must outlive that
-- run, so the holder renews it before each model step. Only the current holder can
-- renew; an expired lease stays expired, so "lease gone" keeps meaning "run is dead".
create function public.renew_ai_turn(p_turn uuid, p_lease uuid, p_ttl_seconds integer default 90)
returns boolean language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); touched integer;
begin
 if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if p_turn is null or p_lease is null or p_ttl_seconds is null or p_ttl_seconds<1 or p_ttl_seconds>300 then
 raise exception 'INVALID_TURN' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_turn::text,0));
 update nb.ai_turn_leases set expires_at=clock_timestamp()+make_interval(secs=>p_ttl_seconds)
 where turn_id=p_turn and user_id=u and lease_id=p_lease and expires_at>clock_timestamp();
 get diagnostics touched=row_count;
 return touched=1;
end;
$$;
revoke all on function public.renew_ai_turn(uuid,uuid,integer) from public,anon;
grant execute on function public.renew_ai_turn(uuid,uuid,integer) to authenticated;
