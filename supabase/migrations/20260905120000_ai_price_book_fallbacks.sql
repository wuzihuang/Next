-- Fallback models have their own Beijing list prices. Billing still
-- looks up by model_id and only uses '*' when the row is missing.

insert into nb.ai_price_book(
  model_id,
  prompt_fen_per_million,
  cached_fen_per_million,
  completion_fen_per_million
)
values
  ('kimi-k3', 2000, 250, 10000),
  ('deepseek-v4-flash', 100, 13, 200)
on conflict (model_id) do update
set
  prompt_fen_per_million = excluded.prompt_fen_per_million,
  cached_fen_per_million = excluded.cached_fen_per_million,
  completion_fen_per_million = excluded.completion_fen_per_million;
