-- Profile › REPORT A PROBLEM replaces EXPORT MY DATA. The `feedback` Edge Function files one
-- GitHub issue per report; screenshots go to a public bucket under an unguessable path so the
-- issue can embed them by URL. `export` keeps its budget row: the function still exists for
-- account-archive work even though the profile no longer has a row for it.
--
-- The budget function is text-patched, not restated: it has been redefined in four migrations
-- and copying any one body reverts what the others added (20260910110000 learned this).

alter table nb.request_budgets drop constraint if exists request_budgets_endpoint_check;
alter table nb.request_budgets add constraint request_budgets_endpoint_check
  check (endpoint = any (array['metric-read','meal-commit','meal-operation','turn','archive-data',
    'export','account-delete','meal','asr','sleep-correction','feedback']));

do $do$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.consume_request_budget(uuid,text)'::regprocedure);
  if position('''feedback''' in definition) > 0 then return; end if;
  patched := replace(definition, 'when ''account-delete'' then 6', 'when ''account-delete'' then 6 when ''feedback'' then 5');
  if patched = definition then raise exception 'REQUEST_BUDGET_ANCHOR_MISSING'; end if;
  execute patched;
end $do$;

-- Public read, service-role write only: no client policy, the Edge Function uploads with the
-- service key and hands GitHub the public URL.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('feedback-images','feedback-images',true,3145728,array['image/jpeg','image/png'])
on conflict(id) do nothing;
