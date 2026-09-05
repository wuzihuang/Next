-- Calculation publication is transactional; inputs have independent revisions.
create table nb.profile_history (
  revision bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  effective_day date not null,
  profile jsonb not null,
  unique(user_id,effective_day)
);
alter table nb.profile_history enable row level security;
insert into nb.profile_history(user_id,effective_day,profile)
select user_id, '-infinity'::date,to_jsonb(p) from public.profiles p;

create table nb.calculation_work (
  user_id uuid primary key references auth.users(id) on delete cascade,
  input_revision bigint not null default 1,
  dirty_from date
);
alter table nb.calculation_work enable row level security;
alter table public.daily_results
  add column input_revision bigint,
  add column result_revision uuid,
  add column calculation_as_of timestamptz,
  add column profile_revision bigint;

create function nb.invalidate_calculation(p_user uuid,p_day date) returns void
language sql volatile set search_path='' as $$
 insert into nb.calculation_work(user_id,dirty_from) values(p_user,p_day)
 on conflict(user_id) do update set
 input_revision=nb.calculation_work.input_revision+1,
 dirty_from=least(nb.calculation_work.dirty_from,excluded.dirty_from);
$$;

create function nb.on_calculation_fact() returns trigger
language plpgsql security definer set search_path='' as $$
declare r jsonb; old_r jsonb; tz text; d date; old_d date;
begin
 if tg_op='UPDATE' and to_jsonb(new) is not distinct from to_jsonb(old) then return new; end if;
 r := case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 select timezone into tz from public.profiles where user_id=(r->>'user_id')::uuid;
 if tz is null then return null; end if;
 d := coalesce((r->>'user_day')::date,least(nb.user_day_of(coalesce(r->>'ts',r->>'measured_at')::timestamptz,tz),nb.user_day_of(coalesce(r->>'ts',r->>'measured_at')::timestamptz,coalesce(r->>'sampled_tz',tz))));
 if tg_op='UPDATE' then
   old_r:=to_jsonb(old);
   old_d:=coalesce((old_r->>'user_day')::date,nb.user_day_of(coalesce(old_r->>'ts',old_r->>'measured_at')::timestamptz,tz));
   d:=least(d,old_d);
 end if;
 -- Cross-midnight sleep affects its prior day's replay as well.
 if tg_table_name='sleep_nights' then d:=d-1; end if;
 if d is not null then perform nb.invalidate_calculation((r->>'user_id')::uuid,d); end if;
 return null;
end;
$$;
do $$ declare t text; begin
 foreach t in array array['raw_samples','sleep_nights','meals','weigh_ins','body_composition'] loop
 execute format('create trigger calculation_fact_changed after insert or update or delete on public.%I for each row execute function nb.on_calculation_fact()',t);
 end loop;
end $$;

create function nb.on_calculation_profile() returns trigger
language plpgsql security definer set search_path='' as $$
declare d date;
begin
 if tg_op='UPDATE' and (to_jsonb(new)-array['locale','units_metric','field_sources']) is not distinct from
 (to_jsonb(old)-array['locale','units_metric','field_sources']) then return new; end if;
 d:=case when tg_op='INSERT' then '-infinity'::date else nb.user_day_of(now(),new.timezone) end;
 insert into nb.profile_history(user_id,effective_day,profile) values(new.user_id,d,to_jsonb(new))
 on conflict(user_id,effective_day) do update set profile=excluded.profile;
 perform nb.invalidate_calculation(new.user_id,nb.user_day_of(now(),new.timezone));
 return new;
end;
$$;
create trigger calculation_profile_changed after insert or update on public.profiles
 for each row execute function nb.on_calculation_profile();

create function nb.calculation_profile(p_user uuid,p_day date) returns setof public.profiles
language sql stable set search_path='' as $$
 select (jsonb_populate_record(null::public.profiles,h.profile)).*
 from nb.profile_history h where h.user_id=p_user and h.effective_day<=p_day
 order by h.effective_day desc limit 1;
$$;
create function nb.calculation_clock() returns timestamptz
language sql stable set search_path='' as $$
 select coalesce(nullif(current_setting('nb.calculation_as_of',true),'')::timestamptz,now());
$$;
create function nb.calculation_day() returns date
language sql stable set search_path='' as $$
 select coalesce(nullif(current_setting('nb.calculation_day',true),'')::date,current_date);
$$;

create function nb.calculation_instant(p_user uuid,p_day date) returns timestamptz
language sql stable set search_path='' as $$
 select least(nb.calculation_clock(),b.ends_at)
 from nb.calculation_profile(p_user,p_day) p
 cross join lateral nb.user_day_bounds(p_day,p.timezone) b;
$$;

-- Preserve formulas while explicitly fixing the time/profile dependencies of their inputs.
do $$ declare p record; definition text; begin
 for p in select oid,proname from pg_proc where pronamespace='nb'::regnamespace
 and proname in ('compute_training','compute_fuel','compute_the_call','compute_reserve',
 'reserve_replay','reserve_anchor','fuel_components','compute_segments','night_inputs',
 'night_hrv_parts','night_hrv','refresh_night_hrv','materialize_reserve_curve') loop
 definition:=pg_get_functiondef(p.oid);
 if definition like '%p_user_day%' then
 definition:=replace(definition,'public.profiles','nb.calculation_profile(p_user, p_user_day)');
 if p.proname<>'refresh_night_hrv' then
 definition:=replace(definition,'now()','nb.calculation_instant(p_user,p_user_day)');
 end if;
 definition:=replace(definition,'age(p.birth_date)','age(p_user_day::timestamp, p.birth_date::timestamp)');
 execute definition;
 end if;
 end loop;
end $$;
create or replace function nb.hr_max(p_birth_date date) returns numeric
language sql stable set search_path='' as $$
 select round(208 - 0.7 * extract(year from age(nb.calculation_day()::timestamp,p_birth_date::timestamp))::numeric);
$$;

-- The replay is evaluated once by settle_day. Its two consumers use the same
-- transaction-local value; no persistent duplicate raw/curve store is introduced.
alter function nb.reserve_replay(uuid,date) rename to reserve_replay_uncached;
create function nb.reserve_replay(p_user uuid,p_user_day date)
returns table(ts timestamptz,value numeric,asleep boolean,d_charge numeric,d_basal numeric,d_active numeric,d_stress numeric)
language plpgsql stable set search_path='' as $$
begin
 if current_setting('nb.replay_key',true)=p_user::text||'/'||p_user_day::text then
   return query select * from jsonb_to_recordset(current_setting('nb.replay_data')::jsonb)
   as r(ts timestamptz,value numeric,asleep boolean,d_charge numeric,d_basal numeric,d_active numeric,d_stress numeric);
 else return query select * from nb.reserve_replay_uncached(p_user,p_user_day);
 end if;
end;
$$;

create or replace function nb.materialize_reserve_curve(p_user uuid,p_user_day date)
returns void language plpgsql volatile set search_path='' as $$
declare lo timestamptz; hi timestamptz;
begin
 select b.starts_at,b.ends_at into lo,hi from nb.calculation_profile(p_user,p_user_day) p
 cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b;
 delete from public.reserve_samples s where s.user_id=p_user and s.ts>=lo and s.ts<hi
 and not exists(select 1 from nb.reserve_replay(p_user,p_user_day) r where r.ts=s.ts);
 insert into public.reserve_samples(user_id,ts,value,source)
 select p_user,r.ts,round(r.value)::smallint,'model' from nb.reserve_replay(p_user,p_user_day) r
 on conflict(user_id,ts) do update set value=excluded.value,source=excluded.source
 where (reserve_samples.value,reserve_samples.source) is distinct from (excluded.value,excluded.source);
end;
$$;

-- Keep the established atomic writer and its detail triggers compatible.
do $$ declare definition text; begin
 definition:=pg_get_functiondef('nb.settle_day(uuid,date)'::regprocedure);
 definition:=replace(definition,'begin' || chr(10), 'begin' || chr(10) ||
 '  v_algo := v_algo || ''/calc-1'';' || chr(10) ||
 '  perform set_config(''nb.replay_key'', '''', true);' || chr(10) ||
 '  perform set_config(''nb.replay_data'', (select coalesce(jsonb_agg(to_jsonb(r)), ''[]''::jsonb)::text from nb.reserve_replay_uncached(p_user,p_user_day) r), true);' || chr(10) ||
 '  perform set_config(''nb.replay_key'', p_user::text||''/''||p_user_day::text, true);' || chr(10));
 definition:=replace(definition,'return v_id;', 'perform set_config(''nb.replay_key'', '''', true); return v_id;');
 definition:=replace(definition,'algo_version, inputs_hash, computed_at)',
 'algo_version, inputs_hash, computed_at, input_revision, result_revision, calculation_as_of, profile_revision)');
 definition:=replace(definition,'v_algo, v_hash, now())',
 'v_algo, v_hash, now(), coalesce(nullif(current_setting(''nb.input_revision'',true),''''),''0'')::bigint, extensions.gen_random_uuid(), nb.calculation_clock(), nullif(current_setting(''nb.profile_revision'',true),'''')::bigint)');
 definition:=replace(definition,'computed_at = now()',
 'computed_at = now(), input_revision = excluded.input_revision, result_revision = excluded.result_revision, calculation_as_of = excluded.calculation_as_of, profile_revision = excluded.profile_revision');
 execute definition;
end $$;

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
   n:=n+1;
 end loop;
 update nb.calculation_work set dirty_from=null where user_id=p_user;
 perform set_config('nb.calculation_as_of',coalesce(previous_asof,''),true);
 perform set_config('nb.calculation_day',coalesce(previous_day,''),true);
 insert into public.recompute_log(algo_version,reason,rows_touched) values('calculation-revisions-1',p_reason,n);
 return n;
end;
$$;
create or replace function nb.recompute_range(p_user uuid,p_from date,p_to date)
returns integer language sql security definer set search_path='' as $$
 select nb.recompute_range(p_user,p_from,p_to,'manual');
$$;

create function public.calculation_status(p_from date,p_to date)
returns table(user_day date,result_revision uuid,input_revision bigint,calculation_as_of timestamptz,pending boolean,current_input_revision bigint)
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
 if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>400 then raise exception 'INVALID_RANGE' using errcode='22023'; end if;
 return query select d::date,r.result_revision,r.input_revision,r.calculation_as_of,
 (r.result_revision is null or r.algo_version not like '%/calc-1'
 or (w.dirty_from is not null and d::date>=w.dirty_from)
 or exists(select 1 from nb.calculation_profile(u,d::date) p
 cross join lateral nb.user_day_bounds(d::date,p.timezone) b
 where r.calculation_as_of<least(b.ends_at,date_bin(interval '5 minutes',now(),'2000-01-01'::timestamptz)))),w.input_revision
 from generate_series(p_from,p_to,interval '1 day') d
 left join public.daily_results r on r.user_id=u and r.user_day=d::date
 left join nb.calculation_work w on w.user_id=u;
end;
$$;
revoke all on function public.calculation_status(date,date) from public,anon;
grant execute on function public.calculation_status(date,date) to authenticated;
-- Every helper is private, including copies created when replay was renamed.
do $$ declare p record; begin
 for p in select oid::regprocedure as f from pg_proc where pronamespace='nb'::regnamespace loop
 execute format('revoke execute on function %s from public,anon,authenticated',p.f);
 end loop;
end $$;

-- Moving an already accepted fact between hot and cold storage is not a new input.
-- Private transaction scope cannot be forged by client-set session parameters.
create table nb.calculation_maintenance (
 transaction_id bigint not null,user_id uuid not null references auth.users(id) on delete cascade,
 primary key(transaction_id,user_id)
);
alter table nb.calculation_maintenance enable row level security;
create function nb.calculation_maintenance_begin(p_owner uuid) returns void
language sql volatile set search_path='' as $$
 insert into nb.calculation_maintenance values(txid_current(),p_owner) on conflict do nothing;
$$;
create function nb.calculation_maintenance_end(p_owner uuid) returns void
language sql volatile set search_path='' as $$
 delete from nb.calculation_maintenance where transaction_id=txid_current() and user_id=p_owner;
$$;
do $$ declare definition text; begin
 definition:=pg_get_functiondef('nb.on_calculation_fact()'::regprocedure);
 definition:=replace(definition,' select timezone into tz',
 ' if exists(select 1 from nb.calculation_maintenance where transaction_id=txid_current() and user_id=(r->>''user_id'')::uuid) then return null; end if;'||chr(10)||' select timezone into tz');
 execute definition;
end $$;
revoke all on function nb.calculation_maintenance_begin(uuid),nb.calculation_maintenance_end(uuid) from public,anon,authenticated;
