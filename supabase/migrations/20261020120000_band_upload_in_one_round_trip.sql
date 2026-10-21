create or replace function public.ingest_band_bundle(
  p_domains jsonb,
  p_sleep jsonb default null,
  p_budget_ms integer default null
) returns jsonb
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_budget interval;
  v_deadline timestamptz;
  v_lock_timeout text;
  v_locked boolean := false;
  v_sleep jsonb;
  v_results jsonb := '[]'::jsonb;
  v_entry jsonb;
  v_status text;
  v_index integer := 0;
begin
  if auth.uid() is null then
    raise exception 'UNAUTHENTICATED' using errcode='28000';
  end if;
  if p_domains is null or jsonb_typeof(p_domains) is distinct from 'array' then
    raise exception 'INVALID_BUNDLE' using errcode='22023';
  end if;
  if jsonb_array_length(p_domains)>16 or octet_length(p_domains::text)>8000000
    or (p_sleep is not null and jsonb_typeof(p_sleep) is distinct from 'object') then
    raise exception 'INVALID_BUNDLE' using errcode='22023';
  end if;

  v_budget:=current_setting('statement_timeout')::interval;
  if v_budget>interval '0' and p_budget_ms is not null then
    v_deadline:=statement_timestamp()+least(v_budget*0.6,p_budget_ms*interval '1 millisecond');
  elsif v_budget>interval '0' then
    v_deadline:=statement_timestamp()+v_budget*0.6;
  elsif p_budget_ms is not null then
    v_deadline:=statement_timestamp()+p_budget_ms*interval '1 millisecond';
  end if;

  v_lock_timeout:=current_setting('lock_timeout');
  perform set_config('lock_timeout','2s',true);

  if p_sleep is not null then
    begin
      v_sleep:=jsonb_build_object('ok',public.publish_sleep_night(p_sleep));
    exception when lock_not_available then
      v_sleep:='{"deferred":true}'::jsonb;
      v_locked:=true;
    when others then
      v_sleep:=jsonb_build_object('error',jsonb_build_object('code',sqlstate,'message',sqlerrm));
    end;
  end if;

  for v_entry in select value from jsonb_array_elements(p_domains) loop
    v_index:=v_index+1;
    if v_locked or (v_index>1 and v_deadline is not null and clock_timestamp()>v_deadline) then
      v_results:=v_results||jsonb_build_array(jsonb_build_object('deferred',true));
      continue;
    end if;
    begin
      v_status:=coalesce(v_entry->>'p_status','complete');
      if v_status='pending_sleep' then
        if p_sleep is null then
          raise exception 'INVALID_BUNDLE' using errcode='22023';
        elsif v_sleep ? 'ok' then
          v_status:='complete';
        elsif v_sleep ? 'error' then
          v_status:='failed';
        else
          v_results:=v_results||jsonb_build_array(jsonb_build_object('deferred',true));
          continue;
        end if;
      end if;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('ok',
        public.ingest_band_delta(
          v_entry->>'p_device_key',
          v_entry->>'p_domain',
          (v_entry->>'p_day')::date,
          v_entry->>'p_timezone',
          (v_entry->>'p_start')::timestamptz,
          (v_entry->>'p_end')::timestamptz,
          v_entry->'p_samples',
          v_status,
          coalesce(v_entry->>'p_mapping_version','veepoo-rmssd-v1'),
          (v_entry->>'p_observed_at')::timestamptz,
          coalesce(v_entry->'p_receipts','[]'::jsonb)
        )));
    exception when lock_not_available then
      v_results:=v_results||jsonb_build_array(jsonb_build_object('deferred',true));
      v_locked:=true;
    when others then
      v_results:=v_results||jsonb_build_array(jsonb_build_object('error',
        jsonb_build_object('code',sqlstate,'message',sqlerrm)));
    end;
  end loop;

  perform set_config('lock_timeout',coalesce(v_lock_timeout,''),true);
  return jsonb_build_object('results',v_results,'sleep',v_sleep);
end;
$$;

revoke all on function public.ingest_band_bundle(jsonb,jsonb,integer) from public,anon;
grant execute on function public.ingest_band_bundle(jsonb,jsonb,integer) to authenticated;

create or replace function public.settle_now(p_days integer default 1)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user   uuid := (select auth.uid());
  v_tz     text;
  v_today  date;
  v_back   integer;
  v_budget interval;
  v_prior  text;
  v_lock_prior text;
  v_n      integer;
begin
  if v_user is null then
    raise exception 'UNAUTHENTICATED' using errcode = '28000';
  end if;
  select timezone into v_tz from public.profiles where user_id = v_user;
  if v_tz is null then return 0; end if;
  v_today := nb.user_day_of(now(), v_tz);
  v_back := least(greatest(coalesce(p_days, 1), 0), 14);
  v_budget := coalesce(nullif(current_setting('statement_timeout', true), ''), '0')::interval;
  v_prior := current_setting('nb.calculation_deadline', true);
  if v_budget > interval '0' then
    perform set_config('nb.calculation_deadline', (clock_timestamp() + v_budget * 0.5)::text, true);
  end if;
  v_lock_prior:=current_setting('lock_timeout');
  perform set_config('lock_timeout','1500ms',true);
  begin
    v_n := nb.recompute_range(v_user, v_today - v_back, v_today, 'app');
  exception when lock_not_available then
    v_n := -1;
  end;
  perform set_config('lock_timeout',coalesce(v_lock_prior,''),true);
  perform set_config('nb.calculation_deadline', coalesce(v_prior, ''), true);
  return v_n;
end;
$$;

revoke execute on function public.settle_now(integer) from public,anon;
grant execute on function public.settle_now(integer) to authenticated;

create or replace procedure nb.settle_accounts(p_days integer default 2)
language plpgsql
as $$
declare
  u record;
  v_budget interval;
  v_deadline timestamptz;
  v_today date;
  v_n integer;
  v_failed boolean;
  v_skip uuid[]:='{}'::uuid[];
  v_pass integer:=1;
  v_processed boolean;
begin
  v_budget:=coalesce(nullif(current_setting('statement_timeout',true),''),'0')::interval;
  if v_budget<=interval '0' then v_budget:=interval '2 minutes'; end if;
  v_deadline:=clock_timestamp()+v_budget*0.7;

  loop
    exit when clock_timestamp()>v_deadline or v_pass>6;
    v_processed:=false;
    if v_pass=1 then
      for u in
        select p.user_id,p.timezone
        from public.profiles p
        where p.deletion_requested_at is null
        order by (select max(r.computed_at) from public.daily_results r where r.user_id=p.user_id) asc nulls first,
                 p.user_id
      loop
        exit when clock_timestamp()>v_deadline;
        v_processed:=true;
        v_today:=(timezone(u.timezone,now()))::date;
        perform set_config('nb.calculation_deadline',(clock_timestamp()+interval '4 seconds')::text,true);
        v_failed:=false;
        begin
          v_n:=nb.recompute_range(u.user_id,v_today-p_days,v_today,'cron');
        exception when others then
          raise warning 'settle_accounts failed for %: % (%)',u.user_id,sqlerrm,sqlstate;
          v_n:=0;
          v_failed:=true;
        end;
        if v_failed or v_n=0 then
          v_skip:=array_append(v_skip,u.user_id);
        end if;
        perform set_config('nb.calculation_deadline','',true);
        commit;
      end loop;
    else
      for u in
        select p.user_id,p.timezone
        from public.profiles p
        join nb.calculation_work w on w.user_id=p.user_id and w.dirty_from is not null
        where p.deletion_requested_at is null and not (p.user_id=any(v_skip))
        order by (select max(r.computed_at) from public.daily_results r where r.user_id=p.user_id) asc nulls first,
                 p.user_id
      loop
        exit when clock_timestamp()>v_deadline;
        v_processed:=true;
        v_today:=(timezone(u.timezone,now()))::date;
        perform set_config('nb.calculation_deadline',(clock_timestamp()+interval '4 seconds')::text,true);
        v_failed:=false;
        begin
          v_n:=nb.recompute_range(u.user_id,v_today-p_days,v_today,'cron');
        exception when others then
          raise warning 'settle_accounts failed for %: % (%)',u.user_id,sqlerrm,sqlstate;
          v_n:=0;
          v_failed:=true;
        end;
        if v_failed or v_n=0 then
          v_skip:=array_append(v_skip,u.user_id);
        end if;
        perform set_config('nb.calculation_deadline','',true);
        commit;
      end loop;
    end if;
    exit when not v_processed;
    v_pass:=v_pass+1;
  end loop;
end;
$$;

revoke execute on procedure nb.settle_accounts(integer) from public,anon,authenticated;

select cron.schedule('nb-settle','7 * * * *',$job$ call nb.settle_accounts(2) $job$);
