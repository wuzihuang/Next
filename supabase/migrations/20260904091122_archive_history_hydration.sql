-- Rehydration is an idempotent tier move; hot corrections always take precedence.
alter table public.sample_archives add column hydrated_at timestamptz;
create function public.hydrate_sample_archive(p_owner uuid,p_id uuid,p_checksum text,p_rows jsonb) returns integer
language plpgsql security definer set search_path=public,pg_temp as $$
declare a sample_archives; inserted_count integer;
begin
 perform 1 from profiles where user_id=p_owner and deletion_requested_at is null for update;
 if not found then raise exception 'ACCOUNT_UNAVAILABLE'; end if;
 select * into a from sample_archives where id=p_id and user_id=p_owner for update;
 if not found or a.state<>'verified' or a.checksum is distinct from p_checksum then raise exception 'ARCHIVE_MISMATCH'; end if;
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) <> a.row_count then raise exception 'ARCHIVE_COUNT'; end if;
 if exists(select 1 from jsonb_array_elements(p_rows) r where r->>'user_id' is distinct from p_owner::text
 or r->>'ts' is null or (r->>'ts')::timestamptz < a.range_start or (r->>'ts')::timestamptz > a.range_end)
 or (select min((r->>'ts')::timestamptz) from jsonb_array_elements(p_rows) r) is distinct from a.range_start
 or (select max((r->>'ts')::timestamptz) from jsonb_array_elements(p_rows) r) is distinct from a.range_end then raise exception 'ARCHIVE_RANGE'; end if;
 perform nb.calculation_maintenance_begin(p_owner);
 execute format('insert into public.%I select * from jsonb_populate_recordset(null::public.%I,$1) on conflict do nothing',a.domain,a.domain) using p_rows;
 get diagnostics inserted_count=row_count;
 perform nb.calculation_maintenance_end(p_owner);
 update sample_archives set hydrated_at=now() where id=p_id;
 return inserted_count;
end $$;
revoke all on function public.hydrate_sample_archive(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.hydrate_sample_archive(uuid,uuid,text,jsonb) to service_role;

create function public.release_sample_hydration(p_owner uuid,p_id uuid,p_checksum text,p_rows jsonb) returns integer
language plpgsql security definer set search_path=public,pg_temp as $$
declare a sample_archives; deleted_count integer;
begin
 perform 1 from profiles where user_id=p_owner and deletion_requested_at is null for update;
 if not found then raise exception 'ACCOUNT_UNAVAILABLE'; end if;
 -- Serialize against a concurrent logical write/invalidation. A dirty chain needs
 -- its restored inputs until the last dependent day has been published.
 perform 1 from nb.calculation_work where user_id=p_owner for update;
 if exists(select 1 from nb.calculation_work where user_id=p_owner and dirty_from is not null) then raise exception 'RECOVERY_IN_PROGRESS'; end if;
 -- Reuse full manifest/payload validation, preserving any hot correction.
 perform public.hydrate_sample_archive(p_owner,p_id,p_checksum,p_rows);
 select * into a from sample_archives where id=p_id and user_id=p_owner for update;
 perform nb.calculation_maintenance_begin(p_owner);
 execute format('delete from public.%I s using jsonb_populate_recordset(null::public.%I,$1) r where s.user_id=$2 and to_jsonb(s)=to_jsonb(r)',a.domain,a.domain) using p_rows,p_owner;
 get diagnostics deleted_count=row_count;
 perform nb.calculation_maintenance_end(p_owner);
 update sample_archives set hydrated_at=null where id=p_id;
 return deleted_count;
end $$;
revoke all on function public.release_sample_hydration(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.release_sample_hydration(uuid,uuid,text,jsonb) to service_role;
