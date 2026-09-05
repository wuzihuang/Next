import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { usageFromProvider } from "./cost.ts";

Deno.test("provider usage splits cached prompt tokens out of the billed input", () => {
  assertEquals(
    usageFromProvider({
      promptTokens: 1200,
      completionTokens: 80,
      promptTokensDetails: { cachedTokens: 200 },
    }),
    { promptTokens: 1000, cachedTokens: 200, completionTokens: 80 },
  );
});

Deno.test("missing usage records as zero rather than inventing a bill", () => {
  assertEquals(usageFromProvider(undefined), {
    promptTokens: 0,
    cachedTokens: 0,
    completionTokens: 0,
  });
});
