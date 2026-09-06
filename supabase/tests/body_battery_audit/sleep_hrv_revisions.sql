-- Runs against either the lightweight fixture or a full migrated schema.
begin;
do $$ declare uid uuid:='00000000-0000-0000-0000-000000000016'; r jsonb; h numeric;
begin
 -- Full-schema runs bootstrap their own user; the light harness already has it.
 if to_regclass('auth.users') is not null then
  insert into auth.users(id) values(uid) on conflict do nothing;
 end if;
 insert into public.profiles(user_id,timezone) values(uid,'UTC') on conflict do nothing;
 insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line,raw)
 values(uid,'2026-09-04',270,270,0,'2026-09-04 04:00Z','2026-09-04 08:30Z','0:270','{}') on conflict do nothing;
 -- Exercise the trigger through the same update path used by the sleep outbox.
 update public.sleep_nights set raw='{"hrv":[{"ts":"2026-09-04T04:00:00Z","rmssd_ms":70,"observed_at":"2026-09-04T12:00:00Z"}]}' where user_id=uid and user_day='2026-09-04';
 update public.sleep_nights set raw='{"hrv_invalidated":[{"ts":"2026-09-04T04:00:00Z","observed_at":"2026-09-04T13:00:00Z","reason":"insufficient_adjacent_rr"}]}' where user_id=uid and user_day='2026-09-04';
 select raw into r from public.sleep_nights where user_id=uid and user_day='2026-09-04';
 if exists(select 1 from jsonb_array_elements(r->'hrv')j where j->>'ts'='2026-09-04T04:00:00Z') then raise exception 'minute not revoked'; end if;
 update public.sleep_nights set raw='{"hrv":[{"ts":"2026-09-04T04:00:00Z","rmssd_ms":70}]}' where user_id=uid and user_day='2026-09-04';
 select raw into r from public.sleep_nights where user_id=uid and user_day='2026-09-04';
 if jsonb_array_length(r->'hrv_invalidated')<>1 or exists(select 1 from jsonb_array_elements(r->'hrv')j where j->>'ts'='2026-09-04T04:00:00Z') then raise exception 'stale unversioned outbox resurrected minute'; end if;
 update public.sleep_nights set raw='{"hrv":[{"ts":"2026-09-04T04:00:00Z","rmssd_ms":80,"observed_at":"2026-09-04T13:00:00Z"}]}' where user_id=uid and user_day='2026-09-04';
 select raw into r from public.sleep_nights where user_id=uid and user_day='2026-09-04';
 if exists(select 1 from jsonb_array_elements(r->'hrv')j where j->>'ts'='2026-09-04T04:00:00Z') then raise exception 'equal timestamp resurrected minute'; end if;
 update public.sleep_nights set raw='{"hrv":[{"ts":"2026-09-04T04:00:00Z","rmssd_ms":90,"observed_at":"2026-09-04T14:00:00Z"},{"ts":"2026-09-04T01:00:00Z","rmssd_ms":50},{"ts":"2026-09-04T04:01:00Z","rmssd_ms":"NaN"}]}' where user_id=uid and user_day='2026-09-04';
 select raw into r from public.sleep_nights where user_id=uid and user_day='2026-09-04';
 if not exists(select 1 from jsonb_array_elements(r->'hrv')j where j->>'rmssd_ms'='90') or jsonb_array_length(r->'hrv_invalidated')<>1 then raise exception 'newer valid observation did not restore or lost tombstone'; end if;
 if exists(select 1 from jsonb_array_elements(r->'hrv')j where j->>'rmssd_ms'='NaN' or j->>'ts'='2026-09-04T01:00:00Z') then raise exception 'invalid or out-of-window point accepted'; end if;
 -- Extending a physical sleep window must not let the old window replay erase revocations.
 update public.sleep_nights set wake_at='2026-09-04 08:31Z',raw='{"hrv_invalidated":[{"ts":"2026-09-04T04:00:00Z","observed_at":"2026-09-04T15:00:00Z"}]}' where user_id=uid and user_day='2026-09-04';
 update public.sleep_nights set wake_at='2026-09-04 08:30Z',raw='{"hrv":[{"ts":"2026-09-04T04:00:00Z","rmssd_ms":70,"observed_at":"2026-09-04T12:00:00Z"}]}' where user_id=uid and user_day='2026-09-04';
 select raw into r from public.sleep_nights where user_id=uid and user_day='2026-09-04';
 if exists(select 1 from jsonb_array_elements(r->'hrv')j where j->>'ts'='2026-09-04T04:00:00Z') or not r?'hrv_invalidated' then raise exception 'old overlapping window resurrected revoked minute'; end if;
 update public.sleep_nights set sleep_start='2026-09-04 12:00Z',wake_at='2026-09-04 13:00Z',raw='{"hrv":[]}' where user_id=uid and user_day='2026-09-04';
 select raw into r from public.sleep_nights where user_id=uid and user_day='2026-09-04';
 if r?'hrv_invalidated' or jsonb_array_length(r->'hrv')<>0 then raise exception 'unrelated sleep window inherited old revisions'; end if;
 r:=nb.merge_sleep_hrv('{}',jsonb_build_object('hrv_invalidated',jsonb_build_array(jsonb_build_object('ts','2026-09-04T12:00:00Z','observed_at',now()+interval '1 year'))),'2026-09-04 12:00Z','2026-09-04 13:00Z');
 if r?'hrv' or r->'hrv_invalidated'<>'[]'::jsonb then raise exception 'future tombstone survived normalization or forged an empty native snapshot'; end if;
 if has_function_privilege('authenticated','nb.merge_sleep_hrv(jsonb,jsonb,timestamptz,timestamptz)','execute') then raise exception 'private revision helper exposed'; end if;
 raise notice 'sleep minute revision assertions passed';
end $$;
rollback;
