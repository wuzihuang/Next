import { z } from "npm:zod@3.25.76";

// A receipt can contain far more than 180 characters or twelve numbers. Those are
// evidence, not a reason to reject the entire response. Bound the context after
// validating types; accept omitted/null optional fields without inventing facts.
export const ImageExtract = z.object({
  summary: z.string().min(1),
  visibleText: z.string().nullish(),
  objects: z.array(z.string()).nullish(),
  numericFacts: z.array(z.number().finite()).nullish(),
}).transform((value) => ({
  summary: value.summary.slice(0, 2000),
  visibleText: (value.visibleText ?? "").slice(0, 12000),
  objects: (value.objects ?? []).slice(0, 64).map((s) => s.slice(0, 160)),
  numericFacts: (value.numericFacts ?? []).slice(0, 256),
}));
