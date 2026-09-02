-- 补屏 A · MHMDA consent, rule 05: 「同意入库四字段：consent_version · granted_at · text_sha256 · locale」.
-- Append-only: one row per answer, newest wins. Withdrawing is a row, not an update — the
-- history is the point.
create table public.consents (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  consent_version text not null,
  choice          text not null check (choice in ('granted', 'declined', 'withdrawn')),
  decided_at      timestamptz not null default now(),
  text_sha256     text not null,
  locale          text not null,
  ms_on_screen    integer
);
create index consents_user_idx on public.consents (user_id, decided_at desc);
alter table public.consents enable row level security;
-- F3 §03 · one policy per action, auth.uid() in a sub-select. No update, no delete: append-only.
create policy consents_select_own on public.consents for select to authenticated
  using (user_id = (select auth.uid()));
create policy consents_insert_own on public.consents for insert to authenticated
  with check (user_id = (select auth.uid()));
