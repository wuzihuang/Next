\pset pager off
create table audit_findings(name text, status text, observed jsonb, contract text);
create function audit_check(p_name text, p_ok boolean, p_observed jsonb, p_contract text)
returns void language sql as $$
  insert into audit_findings values(p_name,
    case when p_ok then 'CHECK_PASSED' else 'BUG_REPRODUCED' end,
    p_observed,p_contract);
$$;

do $$
declare a jsonb; b jsonb; c jsonb;
begin
  select value into a from audit_observations where name='wake_5min_then_sleep';
  perform audit_check('wake_after_brief_night_awakening',
    (a->>'wake_value')::int=(a->>'current_value')::int,a,
    'A 5-minute awakening at 04:30 must not freeze the wake value before sleep resumes until 08:00.');

  select value into a from audit_observations where name='early_wake_read_0700';
  select value into b from audit_observations where name='early_wake_read_1700';
  perform audit_check('early_wake_remains_frozen',a->>'wake_value'=b->>'wake_value',
    jsonb_build_object('at_0700',a->'wake_value','at_1700',b->'wake_value'),
    'The same night ending at 03:00 must retain its wake value as daytime samples arrive.');

  select value into a from audit_observations where name='first_night_8h_result';
  select value into b from audit_observations where name='first_night_8h_expected_from20';
  select value into c from audit_observations where name='first_night_prior_day_anchor';
  perform audit_check('first_cross_day_sleep_anchor',
    abs((a->>'wake_value')::numeric-(b->>'value')::numeric)<=0.5,
    jsonb_build_object('wake',a->'wake_value','expected_from20',round((b->>'value')::numeric,3),'prior_day_anchor',c->'anchor'),
    'An otherwise unobserved first 22:00-06:00 night starts from the documented assumed 20.');

  select value into a from audit_observations where name='4h_sleep_in_4h_window';
  select value into b from audit_observations where name='4h_sleep_in_6h_window';
  perform audit_check('aggregate_sleep_conserves_duration',
    b is null,
    jsonb_build_object('4h_window',a->'current_value','6h_window',b->'current_value'),
    'Only 240 measured sleep minutes must not become 360 charging minutes when the wall-clock window is longer.');

  select value into a from audit_observations where name='quiet_120min';
  perform audit_check('quiet_rest_does_not_claim_recharge', (a->>'current_value')::int<50,a,
    'Quiet rest is a documented drain discount, not net charge; absent HRV cannot establish the quiet discount.');

  select value into a from audit_observations where name='one_tick_each_night_14_flat_baseline';
  select value into b from audit_observations where name='one_tick_each_night_14_variable_baseline';
  perform audit_check('sparse_baseline_is_ineligible', (a->>'hrv_nights')::int=0 and (a->>'rhr_nights')::int=0,
    jsonb_build_object('flat_baseline',a->'multiplier','small_variation_baseline',b->'multiplier'),
    'Fourteen one-tick nights remain ineligible; the dense constant-baseline regression separately verifies the variance floor.');
  perform audit_check('sparse_nights_expose_coverage',
    a ? 'hrv_coverage' or a ? 'hrv_tick_count' or a ? 'hrv_bucket_count',a,
    'One tick per night needs coverage metadata; fourteen sparse ticks must not look like fourteen fully observed nights.');

  select value into a from audit_observations where name='malformed_line_disables_fallback';
  perform audit_check('malformed_line_preserves_known_sleep',(a->>'count')::int>0,a,
    'Malformed nonempty sleep_line must not silently discard an otherwise valid 4-hour sleep record.');

  select value into a from audit_observations where name='mixed_288tick_invariants';
  perform audit_check('mixed_ticks_close_and_stay_bounded',
    (a->>'count')::int=288 and (a->>'min')::numeric>=0 and (a->>'max')::numeric<=100
      and (a->>'max_closure_error')::numeric<0.000000001,a,
    'All 288 mixed-signal ticks stay in [0,100] and their four floating attribution terms close, including the zero floor.');

  select value into a from audit_observations where name='no_evidence';
  perform audit_check('no_evidence_stays_unknown',(a->>'count')::int=0,a,
    'A day with no sleep or sensor evidence must not publish a score.');

  select value into a from audit_observations where name='2_worn_ticks_16h_gap';
  perform audit_check('unworn_gap_does_not_drain',
    (a->>'count')::int=2 and abs((a->>'final')::numeric-49.76)<0.000001,a,
    'A sixteen-hour gap holds battery; only its two worn endpoints each spend 0.12.');

  select value into a from audit_observations where name='unbroken_4h';
  perform audit_check('sleep_saturation_matches_closed_form',
    abs((a->>'current_value')::numeric-(95-75*exp(-0.011*1.25*48)))<=0.5,a,
    'Four hours of uninterrupted deep sleep match the closed-form saturation formula from anchor 20.');
end;
$$;

select name,status from audit_findings order by status,name;
select name,observed,contract from audit_findings where status<>'CHECK_PASSED';
select status,count(*) from audit_findings group by status order by status;
