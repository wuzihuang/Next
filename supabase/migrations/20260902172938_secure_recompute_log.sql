-- recompute_log is an operator-only audit surface. It is written solely by the revoked
-- nb.recompute_range security-definer function and must not be exposed through PostgREST.
alter table public.recompute_log enable row level security;

revoke all on table public.recompute_log from anon, authenticated;
revoke all on sequence public.recompute_log_id_seq from anon, authenticated;
