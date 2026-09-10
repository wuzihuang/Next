begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(5);
insert into auth.users(id) values
 ('ad000000-0000-4000-8000-000000000001'),
 ('ad000000-0000-4000-8000-000000000002');
-- ⚠️ `claim_ai_turn` refuses without a granted consent on the account; without these two
-- rows every assertion below died on CONSENT_WITHDRAWN.
insert into public.profiles(user_id,timezone) values
 ('ad000000-0000-4000-8000-000000000001','UTC'),
 ('ad000000-0000-4000-8000-000000000002','UTC')
on conflict(user_id) do update set timezone=excluded.timezone;
insert into public.consents(user_id,consent_version,choice,decided_at,text_sha256,locale)
select u,'v1','granted','2026-09-01 00:00+00','sha','zh-CN'
from unnest(array['ad000000-0000-4000-8000-000000000001'::uuid,'ad000000-0000-4000-8000-000000000002']) u;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ad000000-0000-4000-8000-000000000001', true);
select is((select status from jsonb_to_record(claim_ai_turn('ad000000-0000-4000-8000-0000000000aa','advice',null,'ad000000-0000-4000-8000-0000000000bb')) as r(status text)),
 'claimed', 'the advice turn takes its lease');
select ok(renew_ai_turn('ad000000-0000-4000-8000-0000000000aa','ad000000-0000-4000-8000-0000000000bb',120),
 'the holder renews its own lease');
reset role;
select ok((select expires_at > clock_timestamp() + interval '100 seconds' from nb.ai_turn_leases
 where turn_id='ad000000-0000-4000-8000-0000000000aa'), 'renewal pushes expiry past the original 90 s');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ad000000-0000-4000-8000-000000000001', true);
select ok(not renew_ai_turn('ad000000-0000-4000-8000-0000000000aa','ad000000-0000-4000-8000-0000000000cc',90),
 'another lease id cannot renew');
select set_config('request.jwt.claim.sub', 'ad000000-0000-4000-8000-000000000002', true);
select ok(not renew_ai_turn('ad000000-0000-4000-8000-0000000000aa','ad000000-0000-4000-8000-0000000000bb',90),
 'another account cannot renew');
select * from finish();
rollback;
