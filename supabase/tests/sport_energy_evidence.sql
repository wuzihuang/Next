-- Run only in a disposable migrated database; all fixtures roll back.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select plan(10);

insert into auth.users(id) values
 ('34343434-3434-4434-8434-343434343434'),
 ('45454545-4545-4454-8454-454545454545');
insert into public.profiles(user_id,timezone) values
 ('34343434-3434-4434-8434-343434343434','UTC'),
 ('45454545-4545-4454-8454-454545454545','UTC');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
 ('34343434-3434-4434-8434-343434343434','test','granted','test','en'),
 ('45454545-4545-4454-8454-454545454545','test','granted','test','en');
update nb.calculation_work set dirty_from=null
where user_id='34343434-3434-4434-8434-343434343434';
select set_config('request.jwt.claim.sub','34343434-3434-4434-8434-343434343434',true);
set local role authenticated;

create temporary table energy_receipt as
select public.ingest_sport_energy('[
 {"id":"56565656-5656-4565-8565-565656565650","session_id":"67676767-6767-4676-8676-676767676767","continuity_id":"78787878-7878-4787-8787-787878787878","observed_at":"2026-09-01T04:00:00.125Z","sport_mode":25,"sampled_tz":"UTC","user_id":"45454545-4545-4454-8454-454545454545"},
 {"id":"56565656-5656-4565-8565-565656565651","session_id":"67676767-6767-4676-8676-676767676767","continuity_id":"78787878-7878-4787-8787-787878787878","observed_at":"2026-09-01T04:00:10.125Z","sport_mode":25,"sampled_tz":"UTC"}
]'::jsonb) result;
select is((select result->>'inserted' from energy_receipt),'2','batch inserts running receipts without HR');
select is((select count(*) from public.sport_energy_samples),2::bigint,'RLS owner comes from auth uid');
select is((public.ingest_sport_energy((select jsonb_agg(to_jsonb(s)-'user_id')
 from public.sport_energy_samples s))->>'inserted'),'0','retry is idempotent');
select throws_ok($$select public.ingest_sport_energy('[
 {"id":"56565656-5656-4565-8565-565656565652","session_id":"67676767-6767-4676-8676-676767676767","continuity_id":"78787878-7878-4787-8787-787878787878","observed_at":"2026-09-01T04:00:11Z","sport_mode":24,"sampled_tz":"UTC"}
]'::jsonb)$$,'22023','INVALID_SPORT_ENERGY_SAMPLE','ambiguous mode is rejected');
select throws_ok($$select public.ingest_sport_energy(jsonb_set(
 (select jsonb_agg(to_jsonb(s)-'user_id') from public.sport_energy_samples s),
 '{0,sport_mode}','47'))$$,'23505','SPORT_ENERGY_OPERATION_CONFLICT',
 'same operation id cannot acknowledge different facts');
select is(jsonb_array_length(public.export_all()->'sport_energy_samples'),2,
 'account export includes strength evidence');
reset role;
select ok((select dirty_from from nb.calculation_work
 where user_id='34343434-3434-4434-8434-343434343434')<='2026-09-01'::date,
 'energy evidence invalidates derived results');
select ok(not has_function_privilege('authenticated','nb.strength_energy_ticks(uuid,date)','execute'),
 'internal energy replay is not an arbitrary-user API');

select set_config('request.jwt.claim.sub','45454545-4545-4454-8454-454545454545',true);
set local role authenticated;
select is((select count(*) from public.sport_energy_samples),0::bigint,
 'another account cannot read strength evidence');
reset role;
delete from auth.users where id='34343434-3434-4434-8434-343434343434';
select is((select count(*) from public.sport_energy_samples
 where user_id='34343434-3434-4434-8434-343434343434'),0::bigint,
 'account deletion cascades to strength evidence');

select * from finish();
rollback;
