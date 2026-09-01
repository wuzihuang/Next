-- 12 · THE CALL, and the two deltas it is made of. compute_the_call already returns
-- fat_delta, lean_delta and n_scans; settle_day kept the verdict and dropped the working,
-- so board 12 could print RECOMP but not the two numbers that produced it — and any day
-- other than today fell back to the empty state on an account with six months of scans.
alter table public.daily_results
  add column if not exists fat_delta_7d  numeric(5, 2),
  add column if not exists lean_delta_7d numeric(5, 2),
  add column if not exists scans_7d      smallint;

create or replace function nb.on_result_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_c record;
begin
  select * into v_c from nb.compute_the_call(new.user_id, new.user_day);
  new.fat_delta_7d  := v_c.fat_delta;
  new.lean_delta_7d := v_c.lean_delta;
  new.scans_7d      := v_c.n_scans;
  return new;
end;
$$;

drop trigger if exists daily_results_call_detail on public.daily_results;
create trigger daily_results_call_detail
before insert or update on public.daily_results
for each row execute function nb.on_result_settled();
