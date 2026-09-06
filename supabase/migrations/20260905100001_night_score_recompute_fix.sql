-- ⚠️ Corrects 20260905100000_night_score.sql.
--
-- That migration re-declared nb.recompute_range in order to add one call, and it built its
-- copy from the definition in 20260903120000 — which 20260904085910 had already replaced.
-- Applying it therefore reverted the reproducible-calculation work: the calculation_work
-- row lock that makes concurrent callers wait rather than publish stale output, the dirty
-- range and its 385-day guard, the skip when a day is already settled at this tick and
-- profile revision, and the calculation_as_of / input_revision / profile_revision settings
-- the revision columns are written from.
--
-- This restores 20260904085910's body verbatim and adds the one line that was wanted, so a
-- night's score settles with the day it belongs to. Nothing else about it changes.
create or replace function nb.recompute_range(p_user uuid,p_from date,p_to date,p_reason text default 'manual')
returns integer language plpgsql security definer set search_path='' as $$
declare d date; n integer:=0; w nb.calculation_work; tz text; today date; lo date;
 hi timestamptz; tick timestamptz; profile_rev bigint; previous_asof text; previous_day text;
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
 if w.dirty_from<today-385 then return 0; end if;
 lo:=greatest(lo,today-385);
 previous_asof:=current_setting('nb.calculation_as_of',true);
 previous_day:=current_setting('nb.calculation_day',true);
 for d in select generate_series(lo,least(greatest(p_to,case when w.dirty_from is not null then today else p_to end),today),interval '1 day')::date loop
   select h.revision into profile_rev from nb.profile_history h
     where h.user_id=p_user and h.effective_day<=d order by h.effective_day desc limit 1;
   select ends_at into hi from nb.user_day_bounds(d,(select p.timezone from nb.calculation_profile(p_user,d) p));
   tick:=least(hi,date_bin(interval '5 minutes',now(),'2000-01-01'::timestamptz));
   if exists(select 1 from public.daily_results r where r.user_id=p_user and r.user_day=d
       and r.result_revision is not null and r.algo_version like '%/calc-1' and r.calculation_as_of=tick and r.profile_revision=profile_rev
       and (w.dirty_from is null or d<w.dirty_from)) then continue; end if;
   perform set_config('nb.calculation_day',d::text,true);
   perform set_config('nb.calculation_as_of',tick::text,true);
   perform nb.refresh_night_hrv(p_user,d);
   perform set_config('nb.input_revision',w.input_revision::text,true);
   perform set_config('nb.profile_revision',profile_rev::text,true);
   perform nb.settle_day(p_user,d);
   perform nb.refresh_night_score(p_user,d);
   n:=n+1;
 end loop;
 update nb.calculation_work set dirty_from=null where user_id=p_user;
 perform set_config('nb.calculation_as_of',coalesce(previous_asof,''),true);
 perform set_config('nb.calculation_day',coalesce(previous_day,''),true);
 insert into public.recompute_log(algo_version,reason,rows_touched) values('calculation-revisions-1',p_reason,n);
 return n;
end;
$$;

revoke execute on function nb.recompute_range(uuid, date, date, text) from public, anon, authenticated;
