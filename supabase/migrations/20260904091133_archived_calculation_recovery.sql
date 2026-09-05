-- The rollout cannot reconstruct raw history already deleted before archival existed.
-- Keeping this fixed floor lets retained history age into the cold tier without
-- confusing legitimately absent samples with irreversibly expired legacy data.
create table if not exists nb.calculation_history_coverage (
 singleton boolean primary key default true check(singleton),
 reliable_from timestamptz not null default now()-interval '400 days'
);
alter table nb.calculation_history_coverage enable row level security;
insert into nb.calculation_history_coverage(singleton) values(true) on conflict(singleton) do nothing;
create table if not exists nb.calculation_recovery_scope (
 transaction_id bigint not null,
 user_id uuid not null references auth.users(id) on delete cascade,
 through_day date not null,
 primary key(transaction_id,user_id)
);
alter table nb.calculation_recovery_scope enable row level security;

-- Recovery is bounded and chronological. The normal authenticated settle remains
-- unable to opt itself into historical replay without verified hydrated inputs.
do $$ declare f text;begin
 f:=pg_get_functiondef('nb.recompute_range(uuid,date,date,text)'::regprocedure);
 if position('if w.dirty_from<today-385 then return 0; end if;' in f)=0 then
 if position('nb.calculation_recovery_scope' in f)>0 then return; end if;
 raise exception 'CALCULATION_RECOVERY_PATCH_MISMATCH'; end if;
 f:=replace(f,'previous_asof text; previous_day text;', 'previous_asof text; previous_day text; recovery_to date; last_day date;');
 f:=replace(f,'if w.dirty_from<today-385 then return 0; end if;',
 'select through_day into recovery_to from nb.calculation_recovery_scope where transaction_id=txid_current() and user_id=p_user;'||chr(10)||
 ' if w.dirty_from<today-385 and recovery_to is null then return 0; end if;');
 f:=replace(f,'lo:=greatest(lo,today-385);','if recovery_to is null then lo:=greatest(lo,today-385); end if;');
 f:=replace(f,'least(greatest(p_to,case when w.dirty_from is not null then today else p_to end),today)',
 'least(greatest(p_to,case when w.dirty_from is not null then today else p_to end),today,coalesce(recovery_to,today))');
 f:=replace(f,'   n:=n+1;','   last_day:=d; n:=n+1;');
 f:=replace(f,'update nb.calculation_work set dirty_from=null where user_id=p_user;',
 'update nb.calculation_work set dirty_from=case when recovery_to is not null and last_day<today then last_day+1 else null end where user_id=p_user;');
 execute f;
end $$;

create or replace function public.resume_calculation(p_owner uuid,p_days integer default 7)
returns jsonb language plpgsql security definer set search_path='' as $$
declare w nb.calculation_work; tz text; today date; through_day date; lo timestamptz; hi timestamptz; n integer; next_day date;
begin
 if p_days is null or p_days<1 or p_days>14 then raise exception 'INVALID_RECOVERY_BATCH' using errcode='22023'; end if;
 perform 1 from public.profiles where user_id=p_owner and deletion_requested_at is null for update;
 if not found then raise exception 'ACCOUNT_UNAVAILABLE'; end if;
 select * into w from nb.calculation_work where user_id=p_owner for update;
 if w.dirty_from is null then return jsonb_build_object('rows_touched',0,'pending',false,'next_day',null); end if;
 select timezone into tz from public.profiles where user_id=p_owner;
 today:=nb.user_day_of(now(),tz);
 through_day:=least(w.dirty_from+p_days-1,today);
 select b.starts_at into lo from nb.calculation_profile(p_owner,w.dirty_from-14) p
 cross join lateral nb.user_day_bounds(w.dirty_from-14,p.timezone) b;
 select b.ends_at into hi from nb.calculation_profile(p_owner,through_day) p
 cross join lateral nb.user_day_bounds(through_day,p.timezone) b;
 if lo<(select reliable_from from nb.calculation_history_coverage) then
 raise exception 'HISTORY_BEFORE_RETAINED_COVERAGE'; end if;
 if exists(select 1 from public.sample_archives a where a.user_id=p_owner and a.domain='raw_samples'
 and a.range_start<hi and a.range_end>=lo and (a.state<>'verified' or a.hydrated_at is null)) then
 return jsonb_build_object('rows_touched',0,'pending',true,'next_day',w.dirty_from,'needs_archive',true,'archive_from',lo,'archive_to',hi); end if;
 insert into nb.calculation_recovery_scope values(txid_current(),p_owner,through_day);
 n:=nb.recompute_range(p_owner,w.dirty_from,through_day,'archive_recovery');
 delete from nb.calculation_recovery_scope where transaction_id=txid_current() and user_id=p_owner;
 select dirty_from into next_day from nb.calculation_work where user_id=p_owner;
 return jsonb_build_object('rows_touched',n,'pending',next_day is not null,'next_day',next_day);
end;
$$;
revoke all on function public.resume_calculation(uuid,integer) from public,anon,authenticated;
grant execute on function public.resume_calculation(uuid,integer) to service_role;
