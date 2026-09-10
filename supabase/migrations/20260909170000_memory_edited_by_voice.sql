-- docs/plans/2026-09-09-ai-tool-surface.md · `write{entity:"memory"}`.
--
-- Until now only memory-settle (service role) could write user_memory; the person could
-- only clear it whole. A fact said out loud ("remember my knee is injured") now lands at
-- once, under the user's own JWT, and a fact can be forgotten by index, by text or all.
-- The summary is never touched here: the settle rewrite still owns it.
create or replace function public.edit_user_memory(
  p_op text, p_text text default null, p_index integer default null, p_query text default null, p_all boolean default false
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  u uuid := auth.uid();
  doc public.user_memory%rowtype;
  facts jsonb;
  kept jsonb := '[]'::jsonb;
  item jsonb;
  i integer := 0;
  removed integer := 0;
  today text := to_char(now(), 'YYYY-MM-DD');
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  if (select choice from public.consents where user_id = u order by decided_at desc, id desc limit 1) is distinct from 'granted' then
    raise exception 'CONSENT_REQUIRED' using errcode='42501';
  end if;
  select * into doc from public.user_memory where user_id = u;
  facts := coalesce(doc.facts, '[]'::jsonb);
  if p_op = 'create' then
    if p_text is null or length(btrim(p_text)) = 0 or length(p_text) > 160 then
      raise exception 'INVALID_MEMORY' using errcode='22023';
    end if;
    -- The same sentence twice is one fact with a fresh date.
    for item in select * from jsonb_array_elements(facts) loop
      if lower(item->>'text') <> lower(btrim(p_text)) then kept := kept || item; end if;
    end loop;
    if jsonb_array_length(kept) >= 40 then kept := kept - 0; end if;
    kept := kept || jsonb_build_object('text', btrim(p_text), 'at', today, 'source', 'chat');
    insert into public.user_memory (user_id, summary, facts, token_estimate, updated_at)
    values (u, coalesce(doc.summary, ''), kept, coalesce(doc.token_estimate, 0) + 40, now())
    on conflict (user_id) do update set facts = excluded.facts, token_estimate = excluded.token_estimate, updated_at = now();
    return jsonb_build_object('index', jsonb_array_length(kept) - 1, 'text', btrim(p_text), 'at', today, 'count', jsonb_array_length(kept));
  elsif p_op = 'delete' then
    if doc.user_id is null then raise exception 'NOT_FOUND' using errcode='P0002'; end if;
    if p_all then
      delete from public.user_memory where user_id = u;
      update public.ai_sessions set summarized_at = coalesce(summarized_at, now()) where user_id = u;
      return jsonb_build_object('removed', jsonb_array_length(facts), 'count', 0, 'summary_cleared', true);
    end if;
    for item in select * from jsonb_array_elements(facts) loop
      if (p_index is not null and i = p_index)
         or (p_index is null and p_query is not null and position(lower(p_query) in lower(item->>'text')) > 0) then
        removed := removed + 1;
      else
        kept := kept || item;
      end if;
      i := i + 1;
    end loop;
    if removed = 0 then raise exception 'NOT_FOUND' using errcode='P0002'; end if;
    update public.user_memory set facts = kept, updated_at = now() where user_id = u;
    return jsonb_build_object('removed', removed, 'count', jsonb_array_length(kept));
  else
    raise exception 'INVALID_OP' using errcode='22023';
  end if;
end $$;
revoke all on function public.edit_user_memory(text, text, integer, text, boolean) from public, anon;
grant execute on function public.edit_user_memory(text, text, integer, text, boolean) to authenticated;
