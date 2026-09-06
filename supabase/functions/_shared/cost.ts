export type TokenUsage = {
  promptTokens: number;
  cachedTokens: number;
  completionTokens: number;
  audioSeconds?: number;
};

export type PriceBook = {
  promptFenPerMillion: number;
  cachedFenPerMillion: number;
  completionFenPerMillion: number;
  audioFenPerSecond?: number;
};

/// Beijing qwen3.8-flash: ¥0.8 / ¥0.1 cached / ¥2.7 per million tokens.
export const DEFAULT_PRICE_BOOK: PriceBook = {
  promptFenPerMillion: 80,
  cachedFenPerMillion: 10,
  completionFenPerMillion: 270,
};

/// Beijing kimi-k3: ¥20 / ¥100. Cached input is billed at one eighth.
export const KIMI_PRICE_BOOK: PriceBook = {
  promptFenPerMillion: 2000,
  cachedFenPerMillion: 250,
  completionFenPerMillion: 10000,
};

/// Beijing deepseek-v4-flash: ¥1 / ¥2.
export const DEEPSEEK_PRICE_BOOK: PriceBook = {
  promptFenPerMillion: 100,
  cachedFenPerMillion: 13,
  completionFenPerMillion: 200,
};

export const PRICE_BOOKS: Record<string, PriceBook> = {
  "qwen3-asr-flash": { promptFenPerMillion: 0, cachedFenPerMillion: 0, completionFenPerMillion: 0, audioFenPerSecond: 0.022 },
  "qwen3-asr-flash-realtime": { promptFenPerMillion: 0, cachedFenPerMillion: 0, completionFenPerMillion: 0, audioFenPerSecond: 0.033 },
  "qwen3.8-flash": DEFAULT_PRICE_BOOK,
  "*": DEFAULT_PRICE_BOOK,
  "kimi-k3": KIMI_PRICE_BOOK,
  "deepseek-v4-flash": DEEPSEEK_PRICE_BOOK,
};

export function priceBookFor(modelId: string): PriceBook {
  const audioId = modelId.startsWith("qwen3-asr-flash-realtime-") ? "qwen3-asr-flash-realtime"
    : modelId.startsWith("qwen3-asr-flash-") ? "qwen3-asr-flash" : modelId;
  return PRICE_BOOKS[modelId] ?? PRICE_BOOKS[audioId] ?? PRICE_BOOKS["*"] ?? DEFAULT_PRICE_BOOK;
}

export const DAILY_COST_CAP_FEN = 200;

export function costFen(
  usage: TokenUsage,
  book: PriceBook = DEFAULT_PRICE_BOOK,
): number {
  const millionths = usage.promptTokens * book.promptFenPerMillion +
    usage.cachedTokens * book.cachedFenPerMillion +
    usage.completionTokens * book.completionFenPerMillion;
  return Math.round(millionths + (usage.audioSeconds ?? 0) * (book.audioFenPerSecond ?? 0) * 1_000_000) / 1_000_000;
}

export function usageFromProvider(raw: unknown, providerMetadata?: unknown): TokenUsage {
  const row = (raw ?? {}) as Record<string, unknown>;
  const prompt = numberAt(row, ["promptTokens", "prompt_tokens", "inputTokens"]);
  const completion = numberAt(row, [
    "completionTokens",
    "completion_tokens",
    "outputTokens",
  ]);
  const metadata = (providerMetadata ?? {}) as Record<string, unknown>;
  const metadataCached = Object.values(metadata).reduce<number>((found, value) => {
    if (!value || typeof value !== "object") return found;
    return Math.max(found, numberAt(value as Record<string, unknown>, ["cachedPromptTokens"]));
  }, 0);
  const cached = Math.min(Math.max(0, prompt), Math.max(0,
    numberAt(row, ["cachedTokens", "cached_tokens"]) || nestedCached(row) || metadataCached,
  ));
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
