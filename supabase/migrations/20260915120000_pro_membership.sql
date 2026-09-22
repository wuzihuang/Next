-- NextBody PRO. The phone can read the row; only the service role writes it.
-- Webhook (and billing-sync, which re-reads RevenueCat) are the write path.
-- Edge Functions look at this table before they spend a model turn.

create table public.billing_entitlements (
  owner uuid primary key references auth.users(id) on delete cascade,
  entitlement text not null default 'pro' check (entitlement = 'pro'),
  product_id text,
  store text,
  period_type text,
  expires_at timestamptz,
  will_renew boolean not null default false,
  intro_claimed_at timestamptz,
  rc_app_user_id text,
  observed_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default now()
);

comment on table public.billing_entitlements is
  'PRO entitlement for one health account. RevenueCat webhook is authoritative.';

alter table public.billing_entitlements enable row level security;
revoke all on public.billing_entitlements from public, anon, authenticated;
grant select on public.billing_entitlements to authenticated;
grant all on public.billing_entitlements to service_role;

create policy billing_entitlements_owner_read on public.billing_entitlements
  for select to authenticated
  using (owner = auth.uid());

create index billing_entitlements_expires_idx
  on public.billing_entitlements (expires_at)
  where expires_at is not null;

create function public.require_pro_entitlement_trusted(p_owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  row public.billing_entitlements%rowtype;
  claimed boolean;
  active boolean;
begin
  if p_owner is null then
    raise exception 'OWNER_REQUIRED' using errcode = '22023';
  end if;
  select * into row from public.billing_entitlements where owner = p_owner;
  claimed := row.intro_claimed_at is not null;
  if row.owner is null then
    return jsonb_build_object('allowed', false, 'intro_claimed', false, 'reason', 'missing');
  end if;
  active := (row.expires_at is not null and row.expires_at > clock_timestamp())
         or (row.expires_at is null and row.product_id is not null);
  if active then
    return jsonb_build_object(
      'allowed', true,
      'intro_claimed', claimed,
      'period_type', row.period_type,
      'expires_at', row.expires_at
    );
  end if;
  return jsonb_build_object('allowed', false, 'intro_claimed', claimed, 'reason', 'expired');
end;
$$;

revoke all on function public.require_pro_entitlement_trusted(uuid) from public, anon, authenticated;
grant execute on function public.require_pro_entitlement_trusted(uuid) to service_role;

create function public.apply_billing_entitlement_trusted(
  p_owner uuid,
  p_product_id text,
  p_store text,
  p_period_type text,
  p_expires_at timestamptz,
  p_will_renew boolean,
  p_intro_claimed boolean,
  p_rc_app_user_id text,
  p_observed_at timestamptz default clock_timestamp()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_owner is null then
    raise exception 'OWNER_REQUIRED' using errcode = '22023';
  end if;
  insert into public.billing_entitlements (
    owner, entitlement, product_id, store, period_type, expires_at,
    will_renew, intro_claimed_at, rc_app_user_id, observed_at, updated_at
  ) values (
    p_owner, 'pro', p_product_id, p_store, p_period_type, p_expires_at,
    coalesce(p_will_renew, false),
    case when p_intro_claimed then clock_timestamp() else null end,
    p_rc_app_user_id,
    p_observed_at,
    clock_timestamp()
  )
  on conflict (owner) do update set
    product_id = case when excluded.observed_at >= public.billing_entitlements.observed_at then excluded.product_id else public.billing_entitlements.product_id end,
    store = case when excluded.observed_at >= public.billing_entitlements.observed_at then excluded.store else public.billing_entitlements.store end,
    period_type = case when excluded.observed_at >= public.billing_entitlements.observed_at then excluded.period_type else public.billing_entitlements.period_type end,
    expires_at = case when excluded.observed_at >= public.billing_entitlements.observed_at then excluded.expires_at else public.billing_entitlements.expires_at end,
    will_renew = case when excluded.observed_at >= public.billing_entitlements.observed_at then excluded.will_renew else public.billing_entitlements.will_renew end,
    intro_claimed_at = coalesce(
      public.billing_entitlements.intro_claimed_at,
      excluded.intro_claimed_at
    ),
    rc_app_user_id = coalesce(excluded.rc_app_user_id, public.billing_entitlements.rc_app_user_id),
    observed_at = greatest(excluded.observed_at, public.billing_entitlements.observed_at),
    updated_at = clock_timestamp();
end;
$$;

revoke all on function public.apply_billing_entitlement_trusted(uuid, text, text, text, timestamptz, boolean, boolean, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.apply_billing_entitlement_trusted(uuid, text, text, text, timestamptz, boolean, boolean, text, timestamptz)
  to service_role;
