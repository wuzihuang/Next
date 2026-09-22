-- ADR 0031 · Jev decides a limited class of read-only requests inside /turn. Three things
-- the existing AI accounting cannot express, and this migration adds the minimum for each.
--
-- 1 · A PRICE FOR THE PROVIDER. Without a row of its own, `record_ai_usage_trusted` falls
--     back to the '*' row — which is Qwen's Beijing price, 80 fen per million prompt
--     tokens. Jev's published price is USD 0.042 per million input tokens with output
--     free, so the '*' fallback would overstate a routing call by roughly 250×. An
--     unpriced provider must never be silently billed at another provider's rate.
--
--     The conversion is explicit and recorded here rather than inferred at runtime:
--         USD 0.042 / Mtok × 7.20 CNY/USD = CNY 0.3024 / Mtok = 30.24 fen / Mtok
--     `prompt_fen_per_million` is an integer column, so this rounds UP to 31 — the
--     accounting may overstate this provider, never understate it. The FX rate is a fixed
--     accounting rate for this price version, not a live quote; revisit both together.
--     Cached input is priced the same as fresh input because the provider documents no
--     cached-input discount; assuming one would under-bill.
--     Output tokens are free per the published price, so completion is 0.
--     Price checked 2026-09-20 at https://docs.typesafe.ai/models (jev-1.13.0: $42/Btok,
--     $0.042/Mtok, "Charged per input token. Output tokens are free.").
--
-- 2 · IDEMPOTENT USAGE ROWS. `nb.ai_model_calls` has no natural key, so a replayed record
--     call double-charges the day. Attempts now carry their own id, unique per user.
--     A real retry is a different attempt id and is billed again, as it should be.
--
-- 3 · COST STATE. An attempt can be served and billed while its usage never reaches us
--     (a cut connection, a timeout in flight, an unusable body). Recording nothing would
--     book a paid call as free. Such a row is written with a conservative upper bound and
--     marked 'unknown': it counts against the day's spend cap like any other cost, and it
--     is visibly an estimate rather than a bill.
--
-- Backward compatible on purpose: the new parameters default, so every existing caller
-- keeps working unchanged, and existing rows read as 'reported' with no attempt id.

-- ---------------------------------------------------------------- 1 · price
insert into nb.ai_price_book(
  model_id, prompt_fen_per_million, cached_fen_per_million, completion_fen_per_million, audio_fen_per_second)
values ('jev-1.13.0', 31, 31, 0, 0)
on conflict (model_id) do update set
  prompt_fen_per_million = excluded.prompt_fen_per_million,
  cached_fen_per_million = excluded.cached_fen_per_million,
  completion_fen_per_million = excluded.completion_fen_per_million,
  audio_fen_per_second = excluded.audio_fen_per_second;

-- ---------------------------------------------------------------- 2 · attempt identity
alter table nb.ai_model_calls add column if not exists logical_call_id text;
alter table nb.ai_model_calls add column if not exists attempt_id uuid;
-- ---------------------------------------------------------------- 3 · cost state
alter table nb.ai_model_calls add column if not exists cost_state text not null default 'reported';
alter table nb.ai_model_calls drop constraint if exists ai_model_calls_cost_state_check;
alter table nb.ai_model_calls add constraint ai_model_calls_cost_state_check
  check (cost_state in ('reported', 'unknown'));

-- One row per real attempt. Partial so the rows written before this migration, and any
-- caller that does not supply an attempt, keep their existing behaviour.
create unique index if not exists ai_model_calls_attempt_key
  on nb.ai_model_calls(user_id, attempt_id) where attempt_id is not null;

create or replace function public.record_ai_usage_trusted(
 p_owner uuid,p_endpoint text,p_model text,p_prompt integer,p_cached integer,
 p_completion integer,p_turn uuid,p_latency integer,p_audio_seconds numeric default 0,
 p_logical_call text default null,p_attempt uuid default null,p_cost_state text default 'reported'
) returns void language plpgsql security definer set search_path='' as $$
declare book nb.ai_price_book%rowtype; fen numeric(20,6); today date; inserted integer;
begin
 if p_owner is null or not exists(select 1 from auth.users where id=p_owner) then
  raise exception 'UNAUTHENTICATED' using errcode='28000';
 end if;
 if p_endpoint not in ('turn','meal','asr','memory') then raise exception 'UNKNOWN_ENDPOINT' using errcode='22023'; end if;
 if p_prompt is null or p_cached is null or p_completion is null or least(p_prompt,p_cached,p_completion)<0 then
  raise exception 'INVALID_USAGE' using errcode='22023';
 end if;
 if p_audio_seconds is null or p_audio_seconds<0 then raise exception 'INVALID_USAGE' using errcode='22023'; end if;
 if p_cost_state is null or p_cost_state not in ('reported','unknown') then
  raise exception 'INVALID_COST_STATE' using errcode='22023';
 end if;
 select * into book from nb.ai_price_book where model_id=p_model;
 if not found and p_model like 'qwen3-asr-flash-%' then
  select * into book from nb.ai_price_book where model_id=case
   when p_model like 'qwen3-asr-flash-realtime-%' then 'qwen3-asr-flash-realtime' else 'qwen3-asr-flash' end;
 end if;
 if not found then select * into book from nb.ai_price_book where model_id='*'; end if;
 -- Cast before multiplication: big model/token counts must not overflow int4.
 fen:=(p_prompt::numeric*book.prompt_fen_per_million + p_cached::numeric*book.cached_fen_per_million
   + p_completion::numeric*book.completion_fen_per_million)/1000000 + p_audio_seconds*book.audio_fen_per_second;
 today:=nb.user_day(p_owner);
 -- An attempt is recorded once. A replay of the same attempt is the same row and must not
 -- charge the day twice; a genuine retry carries a different attempt id.
 insert into nb.ai_model_calls(user_id,user_day,endpoint,turn_id,model_id,prompt_tokens,cached_tokens,completion_tokens,cost_fen,latency_ms,audio_seconds,logical_call_id,attempt_id,cost_state)
 values(p_owner,today,p_endpoint,p_turn,p_model,p_prompt,p_cached,p_completion,fen,p_latency,p_audio_seconds,p_logical_call,p_attempt,p_cost_state)
 on conflict (user_id,attempt_id) where attempt_id is not null do nothing;
 get diagnostics inserted = row_count;
 -- Nothing inserted means this exact attempt was already on the books.
 if inserted = 0 then return; end if;
 -- A row born here takes the same defaults as one born in the admission path.
 insert into nb.ai_quotas(user_id,settled_day,spent_fen,spent_day)
 values(p_owner,today,fen,today)
 on conflict(user_id) do update set
 spent_fen=case when nb.ai_quotas.spent_day=today then nb.ai_quotas.spent_fen+fen else fen end,
 spent_day=today;
end $$;

revoke all on function public.record_ai_usage_trusted(uuid,text,text,integer,integer,integer,uuid,integer,numeric,text,uuid,text) from public,anon,authenticated;
grant execute on function public.record_ai_usage_trusted(uuid,text,text,integer,integer,integer,uuid,integer,numeric,text,uuid,text) to service_role;

-- The nine-argument form is replaced by the twelve-argument one above; leaving both would
-- make a nine-argument call ambiguous.
drop function if exists public.record_ai_usage_trusted(uuid,text,text,integer,integer,integer,uuid,integer,numeric);
