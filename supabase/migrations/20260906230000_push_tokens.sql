-- APNs device tokens. One phone can rotate the token; the pair (user, token) is the row.
-- ON DELETE CASCADE from auth.users covers a hard delete; account-delete also lists the table.
create table public.push_tokens (
  user_id     uuid not null references auth.users (id) on delete cascade,
  token       text not null,
  environment text not null check (environment in ('development', 'production')),
  updated_at  timestamptz not null default now(),
  primary key (user_id, token)
);
create index push_tokens_user_idx on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
create policy push_tokens_select on public.push_tokens
  for select to authenticated using (user_id = (select auth.uid()));
create policy push_tokens_insert on public.push_tokens
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy push_tokens_update on public.push_tokens
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy push_tokens_delete on public.push_tokens
  for delete to authenticated using (user_id = (select auth.uid()));
