-- Cold evidence is private Storage; PostgreSQL holds manifests, never a second full payload.
create table public.sample_archives (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 domain text not null check (domain in ('raw_samples','band_rr_evidence')),
 object_path text not null unique,
 state text not null default 'pending' check (state in ('pending','verified')),
 checksum text not null check (checksum ~ '^[0-9a-f]{64}$'),
 row_count integer not null check (row_count between 1 and 5000),
 range_start timestamptz not null, range_end timestamptz not null,
 format_version integer not null check (format_version = 1),
 created_at timestamptz not null default now(), verified_at timestamptz,
 check (range_start <= range_end),
 check (object_path like user_id::text || '/%'),
 check ((state = 'verified') = (verified_at is not null))
);
create index sample_archives_owner_range on public.sample_archives(user_id,domain,range_end,range_start) where state='verified';
alter table public.sample_archives enable row level security;
grant select on public.sample_archives to authenticated;
create policy archive_owner_read on public.sample_archives for select to authenticated
using (user_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.user_id=sample_archives.user_id and p.deletion_requested_at is null));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('sample-history','sample-history',false,16777216,array['application/gzip']) on conflict(id) do nothing;
create policy archive_object_read on storage.objects for select to authenticated using (
 bucket_id='sample-history' and exists(select 1 from public.sample_archives a where a.object_path=name and a.user_id=(select auth.uid())));
-- Only the authenticated archive worker may upload to its already prepared immutable path.
create policy archive_object_insert on storage.objects for insert to authenticated with check (
 bucket_id='sample-history' and exists(select 1 from public.sample_archives a where a.object_path=name and a.user_id=(select auth.uid()) and a.state='pending'));

-- Service-only preparation serializes against account tombstoning. Never accept a client
-- assertion that an archive is verified or allow a client to prune its own hot evidence.
create function public.prepare_sample_archive(p_owner uuid,p_manifest jsonb,p_path text) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare archive_id uuid;
begin
 perform 1 from profiles where user_id=p_owner and deletion_requested_at is null for update;
 if not found then raise exception 'ACCOUNT_UNAVAILABLE'; end if;
 if exists(select 1 from sample_archives a where a.user_id=p_owner and to_jsonb(a)->>'hydrated_at' is not null) then raise exception 'RECOVERY_IN_PROGRESS'; end if;
 if p_manifest->>'user_id' is distinct from p_owner::text then raise exception 'OWNER_MISMATCH'; end if;
 insert into sample_archives(user_id,domain,object_path,checksum,row_count,range_start,range_end,format_version)
 values(p_owner,p_manifest->>'domain',p_path,p_manifest->>'checksum',(p_manifest->>'row_count')::int,
 (p_manifest->>'range_start')::timestamptz,(p_manifest->>'range_end')::timestamptz,(p_manifest->>'format_version')::int)
 returning id into archive_id;
 return archive_id;
end $$;
revoke all on function public.prepare_sample_archive(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.prepare_sample_archive(uuid,jsonb,text) to service_role;

create function public.finalize_sample_archive(p_owner uuid,p_id uuid,p_checksum text,p_rows jsonb) returns integer
language plpgsql security definer set search_path=public,pg_temp as $$
declare a sample_archives; deleted_count integer; target_table text;
begin
 perform 1 from profiles where user_id=p_owner and deletion_requested_at is null for update;
 if not found then raise exception 'ACCOUNT_UNAVAILABLE'; end if;
 select * into a from sample_archives where id=p_id and user_id=p_owner for update;
 if not found or a.checksum is distinct from p_checksum then raise exception 'ARCHIVE_MISMATCH'; end if;
 if a.state='verified' then return 0; end if;
 if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) <> a.row_count then raise exception 'ARCHIVE_COUNT'; end if;
 if exists(select 1 from jsonb_array_elements(p_rows) r where r->>'user_id' is distinct from p_owner::text
 or (r->>'ts')::timestamptz < a.range_start or (r->>'ts')::timestamptz > a.range_end
 or (r->>'ts')::timestamptz >= now()-interval '400 days') then raise exception 'ARCHIVE_RANGE'; end if;
 if (select min((r->>'ts')::timestamptz) from jsonb_array_elements(p_rows) r) is distinct from a.range_start
 or (select max((r->>'ts')::timestamptz) from jsonb_array_elements(p_rows) r) is distinct from a.range_end then raise exception 'ARCHIVE_RANGE'; end if;
 -- Table name is a constrained manifest domain, quoted defensively. Comparing complete
 -- typed records preserves any hot row changed after the archival snapshot was read.
 target_table:=a.domain;
 perform nb.calculation_maintenance_begin(p_owner);
 execute format('delete from public.%I s using jsonb_populate_recordset(null::public.%I,$1) r where s.user_id=$2 and to_jsonb(s)=to_jsonb(r)',target_table,target_table) using p_rows,p_owner;
 get diagnostics deleted_count=row_count;
 perform nb.calculation_maintenance_end(p_owner);
 update sample_archives set state='verified',verified_at=now() where id=p_id;
 return deleted_count;
end $$;
revoke all on function public.finalize_sample_archive(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.finalize_sample_archive(uuid,uuid,text,jsonb) to service_role;

-- Failed archival postpones raw pruning. Only the verified finalizer removes exact rows.
create or replace function public.prune_retention() returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 delete from public.screen_frames where created_at < now()-interval '90 days';
 delete from public.analytics_events where server_ts < now()-interval '180 days';
end $$;
revoke execute on function public.prune_retention() from public,anon,authenticated;

-- Storage's service client bypasses RLS. A database guard also serializes the actual
-- object insertion with tombstoning, including scheduled workers and crash races.
create function nb.guard_archive_object() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare owner_id uuid;
begin
 if new.bucket_id <> 'sample-history' then return new; end if;
 select user_id into owner_id from public.sample_archives where object_path=new.name and state='pending';
 if owner_id is null then raise exception 'ARCHIVE_NOT_PREPARED'; end if;
 perform 1 from public.profiles where user_id=owner_id and deletion_requested_at is null for update;
 if not found then raise exception 'ACCOUNT_UNAVAILABLE'; end if;
 return new;
end $$;
revoke all on function nb.guard_archive_object() from public,anon,authenticated;
create trigger sample_history_active_owner before insert on storage.objects
for each row execute function nb.guard_archive_object();
