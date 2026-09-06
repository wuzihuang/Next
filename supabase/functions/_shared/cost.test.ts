import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { costFen, DEFAULT_PRICE_BOOK, priceBookFor, type PriceBook } from "./cost.ts";

Deno.test("one million prompt tokens cost eight tenths of a yuan at the published book", () => {
  assertEquals(costFen({ promptTokens: 1_000_000, cachedTokens: 0, completionTokens: 0 }), 80);
});

Deno.test("cached prompt tokens are billed at one eighth of the input price", () => {
  assertEquals(costFen({ promptTokens: 0, cachedTokens: 1_000_000, completionTokens: 0 }), 10);
});

Deno.test("one million completion tokens cost two yuan seventy fen", () => {
  assertEquals(costFen({ promptTokens: 0, cachedTokens: 0, completionTokens: 1_000_000 }), 270);
});

Deno.test("a mixed call folds cached input at the discounted rate", () => {
  assertEquals(
    costFen({ promptTokens: 500_000, cachedTokens: 500_000, completionTokens: 100_000 }),
    72,
  );
});

Deno.test("a different price book changes the same token mix", () => {
  const cheap: PriceBook = {
    promptFenPerMillion: 40,
    cachedFenPerMillion: 5,
    completionFenPerMillion: 100,
  };
  assertEquals(
    costFen({ promptTokens: 1_000_000, cachedTokens: 0, completionTokens: 0 }, cheap),
    40,
  );
  assertEquals(DEFAULT_PRICE_BOOK.promptFenPerMillion, 80);
});

Deno.test("fallback models keep their own Beijing list prices", () => {
  assertEquals(priceBookFor("kimi-k3").promptFenPerMillion, 2000);
  assertEquals(priceBookFor("kimi-k3").completionFenPerMillion, 10000);
  assertEquals(
    costFen({ promptTokens: 1_000_000, cachedTokens: 0, completionTokens: 0 }, priceBookFor("kimi-k3")),
    2000,
  );
  assertEquals(priceBookFor("deepseek-v4-flash").promptFenPerMillion, 100);
  assertEquals(priceBookFor("deepseek-v4-flash").completionFenPerMillion, 200);
  assertEquals(priceBookFor("unknown-model").promptFenPerMillion, 80);
});

Deno.test("small calls retain fractional fen instead of rounding each call up", () => {
  assertEquals(costFen({ promptTokens: 10, cachedTokens: 0, completionTokens: 0 }), 0.0008);
});

Deno.test("ASR is charged by audio duration rather than text tokens", () => {
  assertEquals(costFen({ promptTokens: 100, cachedTokens: 0, completionTokens: 200, audioSeconds: 10 },
    priceBookFor("qwen3-asr-flash")), 0.22);
  assertEquals(costFen({ promptTokens: 0, cachedTokens: 0, completionTokens: 0, audioSeconds: 10 },
    priceBookFor("qwen3-asr-flash-realtime")), 0.33);
  assertEquals(priceBookFor("qwen3-asr-flash-realtime-2026-02-10").audioFenPerSecond, 0.033);
});
