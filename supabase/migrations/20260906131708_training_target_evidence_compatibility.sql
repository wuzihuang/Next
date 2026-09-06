-- Training evidence, compatible with the shared Body Battery 2.1 and sleep-v1.2
-- contracts. No physiological coefficients or goal bands change.

-- This is the shared engineering quality gate (60 covered minutes, at least 50%
-- of recorded sleep minutes, no gap >90 minutes), not clinical calibration.
create function nb.night_evidence(p_user uuid,p_from date,p_to date)
returns table(user_day date,hrv numeric,rhr numeric,hrv_buckets integer,
 hr_slots integer,expected_hrv_buckets integer,expected_hr_slots integer,
 hrv_usable boolean,rhr_usable boolean)
language sql stable set search_path='' as $$
 select n.user_day,e.hrv,e.rhr,e.hrv_bucket_count,ceil(e.rhr_minutes/5.0)::integer,
  ceil(e.expected_minutes/15.0)::integer,ceil(e.expected_minutes/5.0)::integer,
  e.hrv_eligible,e.rhr_eligible
 from nb.canonical_sleep_nights(p_user,p_from,p_to) n cross join lateral nb.night_evidence_parts(p_user,n.user_day) e
 where n.user_id=p_user and n.user_day between p_from and p_to;
$$;

create function nb.hr_rest_details(p_user uuid,p_user_day date,p_tz text)
returns table(resting numeric,nights integer,estimated boolean)
language sql stable set search_path='' as $$
 with monday as (select p_user_day-extract(isodow from p_user_day)::integer+1 as d),
 frozen as materialized (
  select e.* from monday m cross join lateral nb.night_evidence(p_user,m.d-7,m.d-1) e
  where e.rhr_usable
 ), recent as materialized (
  select e.* from nb.night_evidence(p_user,p_user_day-7,p_user_day-1) e
  where e.rhr_usable and (select count(*) from frozen)<3
 ), chosen as (
  select rhr from frozen where (select count(*) from frozen)>=3
  union all select rhr from recent
 )
 select case when count(*)>=3 then round(percentile_cont(0.5) within group(order by rhr)::numeric) end,
   count(*)::integer,(select count(*) from frozen)<3 from chosen;
$$;
create or replace function nb.hr_rest(p_user uuid,p_user_day date,p_tz text)
returns numeric language sql stable set search_path='' as $$
 select d.resting from nb.hr_rest_details(p_user,p_user_day,p_tz) d;
$$;

alter table public.daily_training add column recorded_steps integer,
  add column evidence jsonb;

create function nb.training_observations(p_user uuid,p_user_day date)
returns table(ts timestamptz,heart smallint,steps integer,met numeric,observed boolean)
language sql stable set search_path='' as $$
 with profile as materialized (select * from nb.calculation_profile(p_user,p_user_day)),
 points as (
  select distinct on(date_bin(interval '5 minutes',s.ts,b.starts_at))
    date_bin(interval '5 minutes',s.ts,b.starts_at) t,s.heart,s.step,s.met
  from profile p cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b
  join public.raw_samples s on s.user_id=p_user and s.ts>=b.starts_at and s.ts<b.ends_at
  where s.ts+interval '5 minutes'<=nb.calculation_instant(p_user,p_user_day)
  order by date_bin(interval '5 minutes',s.ts,b.starts_at),(s.src='band') desc,s.ts desc,s.src
 )
 select t,heart,step,met,
   heart between 1 and 250 or met between 0.5 and 25 or step>0
 from points;
$$;

-- Step totals are independent of segmentation. Evidence uses distinct, completed
-- intervals and separates observed movement from mere presence of zero rows.
create function nb.training_evidence(p_user uuid,p_user_day date)
returns jsonb language sql stable set search_path='' as $$
 with profile as materialized (select * from nb.calculation_profile(p_user,p_user_day)),
 details as materialized (select d.* from profile p
   cross join lateral nb.hr_rest_details(p_user,p_user_day,p.timezone) d),
 obs as materialized (select * from nb.training_observations(p_user,p_user_day))
 select jsonb_build_object(
  'elapsed_minutes',floor(extract(epoch from(nb.calculation_instant(p_user,p_user_day)-b.starts_at))/60),
  'recorded_minutes',(select count(*)*5 from obs where observed),
  'hr_minutes',(select count(*)*5 from obs where heart between 1 and 250),
  'movement_minutes',(select count(*)*5 from obs where met between 0.5 and 25 or steps>0),
  'hr_rest',d.resting,'hr_rest_nights',d.nights,'baseline_estimated',d.estimated or d.resting is null,
  'model_kind','activity_estimate')
 from profile p cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b cross join details d;
$$;

create function nb.publish_training_evidence() returns trigger
language plpgsql security definer set search_path='' as $$
declare day date; begin
 select d.user_day into day from public.daily_results d where d.id=new.result_id and d.user_id=new.user_id;
 if day is not null then
  select sum(o.steps)::integer into new.recorded_steps from nb.training_observations(new.user_id,day) o;
  new.evidence:=nb.training_evidence(new.user_id,day);
 end if;
 return new;
end $$;
create trigger training_evidence before insert or update on public.daily_training
for each row execute function nb.publish_training_evidence();

-- Helpers are only called through the existing authenticated publication pipeline.
revoke all on function nb.night_evidence(uuid,date,date),nb.hr_rest_details(uuid,date,text),
 nb.hr_rest(uuid,date,text),nb.training_observations(uuid,date),
 nb.training_evidence(uuid,date),nb.publish_training_evidence() from public,anon,authenticated;

-- Existing publication and replay retain their locks and archive recovery. The
-- new training version makes old completed-day outputs visibly pending too.
do $$ declare def text; patched text; signature text; begin
 foreach signature in array array['nb.settle_day(uuid,date)',
   'nb.recompute_range(uuid,date,date,text)','public.calculation_status(date,date)'] loop
  def:=pg_get_functiondef(signature::regprocedure);
  if signature='nb.settle_day(uuid,date)' then
   patched:=replace(def,'tl-2.1','tl-2.2');
  else
   patched:=replace(def,'%bb-2.1%/calc-1','%tl-2.2%bb-2.1%/calc-1');
  end if;
  if patched=def then raise exception 'TRAINING_VERSION_ANCHOR_MISSING: %',signature; end if;
  execute patched;
 end loop;
end $$;

select nb.invalidate_calculation(user_id,min(user_day)) from public.daily_results group by user_id;
