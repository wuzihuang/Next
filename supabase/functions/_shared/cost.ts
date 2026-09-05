export type TokenUsage = {
  promptTokens: number;
  cachedTokens: number;
  completionTokens: number;
};

export type PriceBook = {
  promptFenPerMillion: number;
  cachedFenPerMillion: number;
  completionFenPerMillion: number;
};

/// Beijing qwen3.8-flash: ¥0.8 / ¥0.1 cached / ¥2.7 per million tokens.
export const DEFAULT_PRICE_BOOK: PriceBook = {
  promptFenPerMillion: 80,
  cachedFenPerMillion: 10,
  completionFenPerMillion: 270,
};

export const DAILY_COST_CAP_FEN = 200;

export function costFen(
  usage: TokenUsage,
  book: PriceBook = DEFAULT_PRICE_BOOK,
): number {
  const millionths = usage.promptTokens * book.promptFenPerMillion +
    usage.cachedTokens * book.cachedFenPerMillion +
    usage.completionTokens * book.completionFenPerMillion;
  return Math.ceil(millionths / 1_000_000);
}

export function usageFromProvider(raw: unknown): TokenUsage {
  const row = (raw ?? {}) as Record<string, unknown>;
  const prompt = numberAt(row, ["promptTokens", "prompt_tokens", "inputTokens"]);
  const completion = numberAt(row, [
    "completionTokens",
    "completion_tokens",
    "outputTokens",
  ]);
  const cached = numberAt(row, ["cachedTokens", "cached_tokens"]) ||
    nestedCached(row);
  return {
    promptTokens: Math.max(0, prompt - cached),
    cachedTokens: Math.max(0, cached),
    completionTokens: Math.max(0, completion),
  };
}

function numberAt(row: Record<string, unknown>, keys: string[]): number {
  for (const key of keys) {
    const value = row[key];
    if (typeof value === "number" && Number.isFinite(value)) return value;
  }
  return 0;
}

function nestedCached(row: Record<string, unknown>): number {
  const details = row.promptTokensDetails ?? row.prompt_tokens_details;
  if (!details || typeof details !== "object") return 0;
  return numberAt(details as Record<string, unknown>, [
    "cachedTokens",
    "cached_tokens",
  ]);
}
