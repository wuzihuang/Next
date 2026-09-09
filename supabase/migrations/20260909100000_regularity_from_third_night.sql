-- ADR 0008 · the regularity group scores from the third recorded night, not the fourteenth.
--
-- sleep-v1 held regularity silent until 14 canonical nights had accumulated in the trailing
-- 28 days, on the grounds that "on time" is only definable against the person's own median.
-- The definability argument holds; the sample size did not: the group prints NO BASELINE
-- YET for the first two weeks of every account, which is the whole period a new wearer is
-- deciding whether the band knows them. A median of three bedtimes is a coarse habit, but
-- full marks already span ±30 minutes and zero is 120 minutes out, so a coarse median
-- cannot produce a wrong verdict, only a slightly late one. The HRV / RHR personal weights
-- keep their 14→28 ramp; only the bedtime baseline changes here.
--
-- Text-patch on the live definition (as 20260906130405 did for the version literal) so this
-- rides on whatever the latest night_score_parts body is instead of freezing a copy of it.
-- Both anchors must be present: the scoring gate and the bed_median publication gate.
do $$ declare definition text; patched text; begin
 definition:=pg_get_functiondef('nb.night_score_parts(uuid,date)'::regprocedure);
 patched:=replace(definition,'bed_n>=14','bed_n>=3');
 if patched=definition then raise exception 'REGULARITY_THRESHOLD_ANCHOR_MISSING'; end if;
 if (length(definition)-length(replace(definition,'bed_n>=14','')))/length('bed_n>=14')<>2
  then raise exception 'REGULARITY_THRESHOLD_ANCHOR_COUNT'; end if;
 execute patched;

 definition:=pg_get_functiondef('nb.refresh_night_score(uuid,date)'::regprocedure);
 patched:=replace(definition,'''sleep-v1.2''','''sleep-v1.3''');
 if patched=definition then raise exception 'SLEEP_V13_VERSION_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

comment on column public.night_score.regularity_score is
 'Bedtime distance from this person''s own median over the trailing 28 nights; full marks within 30 minutes, zero at 120. Null until three canonical prior nights exist (sleep-v1.3; was fourteen).';

-- An algorithm change is a full recompute (ADR 0008). One row per night per user.
do $$
declare r record; n integer := 0;
begin
  for r in select user_id, user_day from public.night_score where score_version <> 'sleep-v1.3'
  loop
    perform nb.refresh_night_score(r.user_id, r.user_day);
    n := n + 1;
  end loop;
  raise notice 'night_score: resettled % row(s) onto sleep-v1.3', n;
end $$;
