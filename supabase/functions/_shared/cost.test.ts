import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { costFen, DEFAULT_PRICE_BOOK, type PriceBook } from "./cost.ts";

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
