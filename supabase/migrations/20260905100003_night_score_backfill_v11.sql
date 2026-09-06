-- ADR 0008 · an algorithm change means a full recompute, and 20260905100002 changed one.
--
-- That migration bumped the version to sleep-v1.1 but left the rows already settled under
-- sleep-v1 where they were, so a week window would have mixed two algorithms across its
-- seven bars with nothing on the chart saying which was which. Every stale row is settled
-- again here. The table is one row per night per user and rebuilding it is the reason it
-- was made a derived table of its own rather than columns on sleep_nights.
do $$
declare r record; n integer := 0;
begin
  for r in select user_id, user_day from public.night_score where score_version <> 'sleep-v1.1'
  loop
    perform nb.refresh_night_score(r.user_id, r.user_day);
    n := n + 1;
  end loop;
  raise notice 'night_score: resettled % row(s) onto sleep-v1.1', n;
end $$;
