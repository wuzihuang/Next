-- DELETE EVERYTHING timed out on any account that had worn a band for a while.
--
-- account-delete removed the account table by table over PostgREST, and every row of
-- raw_samples fires calculation_fact_changed, which invalidates that row's day. A month of
-- minute samples (52k rows, the review account) took 43 s on its own; the phones give up
-- at 30 s and the sheet then sat there with nothing to say. The calculation trigger already
-- has a way out for exactly this — calculation_maintenance, which the archive paths use —
-- and every public and nb table carrying a user_id cascades from auth.users, so one
-- delete of the auth user inside a maintenance window is the whole wipe. Measured on the
-- same account: 0.74 s.
--
-- ⚠️ Storage is not covered by the cascade. The endpoint still empties the buckets first,
-- and only then calls this.
create function nb.purge_account(p_owner uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_owner is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  perform nb.calculation_maintenance_begin(p_owner);
  delete from auth.users where id = p_owner;
  perform nb.calculation_maintenance_end(p_owner);
end $$;
revoke all on function nb.purge_account(uuid) from public, anon, authenticated;

create function public.purge_account(p_owner uuid) returns jsonb
language sql security definer set search_path = '' as $$
  select nb.purge_account(p_owner);
  select jsonb_build_object('deleted', not exists(select 1 from auth.users where id = p_owner));
$$;
revoke all on function public.purge_account(uuid) from public, anon, authenticated;
grant execute on function public.purge_account(uuid) to service_role;
