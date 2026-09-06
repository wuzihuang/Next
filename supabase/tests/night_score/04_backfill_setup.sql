-- These rows exist before the migration; verify full rebuild and retained source history.
create table t_backfill(user_id uuid);
create table t_migration_guards(definition text);
create table t_shared_function_guards(name text,definition text);
insert into t_shared_function_guards select name,pg_get_functiondef(name::regprocedure)
 from unnest(array['nb.night_hrv_parts(uuid,date)','nb.night_rhr(uuid,date,text)']) name;
insert into t_migration_guards select pg_get_functiondef('nb.recompute_range(uuid,date,date,text)'::regprocedure);
do $$ declare u uuid:=gen_random_uuid(); begin
 insert into auth.users values(u);
 insert into public.profiles(user_id,timezone) values(u,'Asia/Shanghai');
 insert into t_backfill values(u);
 insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_start,wake_at,raw)
 select u,d,450,90,360,1,'2026-09-05T23:30:00+08:00','2026-09-06T07:00:00+08:00',
 '{"hrv":[{"ts":"2026-09-05T23:30:00+08:00","rmssd_ms":20},
          {"ts":"2026-09-06T00:00:00+08:00","rmssd_ms":40}]}'
 from (values('2026-09-05'::date),('2026-09-06'::date)) days(d);
 insert into public.night_hrv(user_id,user_day,rmssd_ms,bucket_count)
 select u,d,99,2 from (values('2026-09-05'::date),('2026-09-06'::date)) days(d);
 perform nb.refresh_night_score(u,'2026-09-05'); perform nb.refresh_night_score(u,'2026-09-06');
 assert (select count(*) from public.night_score where user_id=u)=2;
end $$;
