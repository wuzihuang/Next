begin;
select plan(15);

insert into auth.users(id) values('eeeeeeee-1111-1111-1111-111111111111');
insert into auth.users(id) values('eeeeeeee-2222-2222-2222-222222222222');

select ok(not has_table_privilege('authenticated','public.billing_entitlements','insert'),
  'clients cannot insert their own entitlement');
select ok(not has_table_privilege('authenticated','public.billing_entitlements','update'),
  'clients cannot update their own entitlement');
select ok(not has_function_privilege('authenticated','public.require_pro_entitlement_trusted(uuid)','execute'),
  'clients cannot run the trusted entitlement check');
select ok(not has_function_privilege('authenticated','public.apply_billing_entitlement_trusted(uuid,text,text,text,timestamptz,boolean,boolean,text)','execute'),
  'clients cannot apply an entitlement');

set local role service_role;
select is((public.require_pro_entitlement_trusted('eeeeeeee-1111-1111-1111-111111111111')->>'allowed')::boolean,
  false, 'a health account with no row is not Pro');
select is((public.require_pro_entitlement_trusted('eeeeeeee-1111-1111-1111-111111111111')->>'intro_claimed')::boolean,
  false, 'a health account with no row has not claimed the intro');

select public.apply_billing_entitlement_trusted(
  'eeeeeeee-1111-1111-1111-111111111111',
  'hoop_pro_monthly',
  'app_store',
  'trial',
  clock_timestamp() + interval '20 days',
  true,
  true,
  'eeeeeeee-1111-1111-1111-111111111111'
);
select is((public.require_pro_entitlement_trusted('eeeeeeee-1111-1111-1111-111111111111')->>'allowed')::boolean,
  true, 'an unexpired trial is Pro');
select is((public.require_pro_entitlement_trusted('eeeeeeee-1111-1111-1111-111111111111')->>'intro_claimed')::boolean,
  true, 'a trial start claims the intro');

select public.apply_billing_entitlement_trusted(
  'eeeeeeee-1111-1111-1111-111111111111',
  'hoop_pro_monthly',
  'app_store',
  'normal',
  clock_timestamp() - interval '1 hour',
  false,
  false,
  'eeeeeeee-1111-1111-1111-111111111111'
);
select is((public.require_pro_entitlement_trusted('eeeeeeee-1111-1111-1111-111111111111')->>'allowed')::boolean,
  false, 'an expired period is not Pro');
select is((public.require_pro_entitlement_trusted('eeeeeeee-1111-1111-1111-111111111111')->>'intro_claimed')::boolean,
  true, 'intro_claimed_at is never cleared');

select public.apply_billing_entitlement_trusted(
  'eeeeeeee-2222-2222-2222-222222222222',
  'hoop_pro_monthly',
  'app_store',
  'normal',
  clock_timestamp() + interval '28 days',
  true,
  true,
  'eeeeeeee-2222-2222-2222-222222222222'
);
select is((public.require_pro_entitlement_trusted('eeeeeeee-2222-2222-2222-222222222222')->>'allowed')::boolean,
  true, 'a paid month is Pro');

select public.apply_billing_entitlement_trusted(
  'eeeeeeee-2222-2222-2222-222222222222',
  'hoop_pro_monthly',
  'app_store',
  'normal',
  null,
  false,
  false,
  'eeeeeeee-2222-2222-2222-222222222222'
);
select is((public.require_pro_entitlement_trusted('eeeeeeee-2222-2222-2222-222222222222')->>'allowed')::boolean,
  true, 'a row with a product and no expiry stays Pro');

insert into auth.users(id) values('eeeeeeee-3333-3333-3333-333333333333');
select public.apply_billing_entitlement_trusted(
  'eeeeeeee-3333-3333-3333-333333333333',
  null,
  null,
  null,
  clock_timestamp(),
  false,
  false,
  'eeeeeeee-3333-3333-3333-333333333333'
);
select is((public.require_pro_entitlement_trusted('eeeeeeee-3333-3333-3333-333333333333')->>'allowed')::boolean,
  false, 'a sync with no product and a stamped expiry is not Pro');

reset role;
set local role authenticated;
set local request.jwt.claim.sub = 'eeeeeeee-1111-1111-1111-111111111111';
select is((select count(*)::int from public.billing_entitlements), 1,
  'RLS lets the owner read only their row');

reset role;
select throws_ok(
  $$select public.require_pro_entitlement_trusted(null)$$,
  '22023',
  'OWNER_REQUIRED',
  'a missing owner fails closed'
);

select * from finish();
rollback;
