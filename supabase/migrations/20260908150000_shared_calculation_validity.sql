-- A published result and a skipped replay must agree about the same dependencies.
-- This consolidates the current bb-2.2 / energy-1.1 contract without changing the
-- formula, public RPCs, account lock, chronological dirty range, archive scope or
-- deadline. Future publication version changes belong in calculation_version.
create function nb.calculation_version() returns text
language sql stable set search_path='' as $$
 select 'tl-2.2/bb-2.2/fuel-1.0/call-1.2/energy-1.1/calc-1'::text;
$$;

create function nb.calculation_result_is_current(
 p_result public.daily_results,p_dirty_from date,p_profile_revision bigint,
 p_day_end timestamptz,p_as_of timestamptz)
returns boolean language sql stable set search_path='' as $$
 select coalesce(
  p_result.result_revision is not null
  and p_result.algo_version=nb.calculation_version()
  and p_result.profile_revision=p_profile_revision
  and (p_dirty_from is null or p_result.user_day<p_dirty_from)
  and p_result.calculation_as_of<=least(p_day_end,p_as_of)
  and (p_result.calculation_as_of=p_day_end
    or (p_as_of<p_day_end and p_result.calculation_as_of>p_as_of-interval '5 minutes')),
  false);
$$;

-- One-time replacement at the existing atomic writer's version seam. Keep its
-- publication/triggers/cache unchanged; the version itself now has one owner.
do $$ declare definition text; patched text; begin
 definition:=pg_get_functiondef('nb.settle_day(uuid,date)'::regprocedure);
 patched:=replace(definition,
  'v_algo    text := ''tl-2.2/bb-2.2/fuel-1.0/call-1.2'';',
  'v_algo    text := nb.calculation_version();');
 if patched=definition then raise exception 'CALCULATION_VERSION_DECLARATION_MISSING'; end if;
 definition:=patched;
 patched:=replace(definition,'  v_algo := v_algo || ''/energy-1.1/calc-1'';'||chr(10),'');
 if patched=definition then raise exception 'CALCULATION_VERSION_SUFFIX_MISSING'; end if;
 execute patched;
end $$;

-- Effective definition rebuilt from all preceding local migrations. The only
-- behavioral seam replaced here is the duplicated validity predicate.
CREATE OR REPLACE FUNCTION nb.recompute_range(p_user uuid, p_from date, p_to date, p_reason text DEFAULT 'manual'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d date; n integer:=0; w nb.calculation_work; tz text; today date; lo date;
 hi timestamptz; tick timestamptz; profile_rev bigint; previous_asof text; previous_day text; recovery_to date; last_day date; deadline timestamptz; next_day date;
begin
 -- Fact writers lock the same row when advancing a revision; concurrent callers
 -- recheck this state after waiting rather than publishing stale output.
 insert into nb.calculation_work(user_id) values(p_user) on conflict do nothing;
 select * into w from nb.calculation_work where user_id=p_user for update;
 select timezone into tz from public.profiles where user_id=p_user and deletion_requested_at is null;
 if tz is null then return 0; end if;
 today:=nb.user_day_of(now(),tz);
 lo:=least(p_from,w.dirty_from);
 -- Fourteen baseline nights plus a full local day must remain available.
 -- An old dirty dependency cannot be skipped: its carry-forward would corrupt
 -- later days. Keep the entire chain pending until archive recovery can replay it.
 select through_day into recovery_to from nb.calculation_recovery_scope where transaction_id=txid_current() and user_id=p_user;
 if w.dirty_from<today-385 and recovery_to is null then return 0; end if;
 if recovery_to is null then lo:=greatest(lo,today-385); end if;
 previous_asof:=current_setting('nb.calculation_as_of',true);
 previous_day:=current_setting('nb.calculation_day',true);
 deadline:=nullif(current_setting('nb.calculation_deadline',true),'')::timestamptz;
 for d in select generate_series(lo,least(greatest(p_to,case when w.dirty_from is not null then today else p_to end),today,coalesce(recovery_to,today)),interval '1 day')::date loop
   select h.revision into profile_rev from nb.profile_history h
     where h.user_id=p_user and h.effective_day<=d order by h.effective_day desc limit 1;
   select ends_at into hi from nb.user_day_bounds(d,(select p.timezone from nb.calculation_profile(p_user,d) p));
   tick:=least(hi,date_bin(interval '1 minute',now(),'2000-01-01'::timestamptz));
   if exists(select 1 from public.daily_results r where r.user_id=p_user and r.user_day=d
       and nb.calculation_result_is_current(r,w.dirty_from,profile_rev,hi,tick)) then continue; end if;
   if deadline is not null and last_day is not null and clock_timestamp()>deadline then next_day:=d; exit; end if;
   perform set_config('nb.calculation_day',d::text,true);
   perform set_config('nb.calculation_as_of',tick::text,true);
   perform nb.refresh_night_hrv(p_user,d);
   perform set_config('nb.input_revision',w.input_revision::text,true);
   perform set_config('nb.profile_revision',profile_rev::text,true);
   perform nb.settle_day(p_user,d);
   perform nb.refresh_night_score(p_user,d);
   last_day:=d; n:=n+1;
 end loop;
 update nb.calculation_work set dirty_from=case when next_day is not null then next_day when recovery_to is not null and last_day<today then last_day+1 else null end where user_id=p_user;
 perform set_config('nb.calculation_as_of',coalesce(previous_asof,''),true);
 perform set_config('nb.calculation_day',coalesce(previous_day,''),true);
 insert into public.recompute_log(algo_version,reason,rows_touched) values('calculation-revisions-1',p_reason||case when next_day is not null then ' (deadline, resumes '||next_day||')' else '' end,n);
 return n;
end;
$function$;

create or replace function public.calculation_status(p_from date,p_to date)
returns table(user_day date,result_revision uuid,input_revision bigint,calculation_as_of timestamptz,pending boolean,current_input_revision bigint)
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
 if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>400 then raise exception 'INVALID_RANGE' using errcode='22023'; end if;
 return query select d::date,r.result_revision,r.input_revision,r.calculation_as_of,
  not nb.calculation_result_is_current(r,w.dirty_from,h.revision,b.ends_at,
   date_bin(interval '1 minute',now(),'2000-01-01'::timestamptz)),w.input_revision
 from generate_series(p_from,p_to,interval '1 day') d
 left join public.daily_results r on r.user_id=u and r.user_day=d::date
 left join nb.calculation_work w on w.user_id=u
 left join lateral (
  select p.revision,p.profile->>'timezone' as timezone from nb.profile_history p
  where p.user_id=u and p.effective_day<=d::date order by p.effective_day desc limit 1
 ) h on true
 left join lateral nb.user_day_bounds(d::date,h.timezone) b on true;
end;
$$;

revoke all on function nb.calculation_version(),
 nb.calculation_result_is_current(public.daily_results,date,bigint,timestamptz,timestamptz),
 nb.recompute_range(uuid,date,date,text),nb.settle_day(uuid,date) from public,anon,authenticated;
revoke all on function public.calculation_status(date,date) from public,anon;
grant execute on function public.calculation_status(date,date) to authenticated;
