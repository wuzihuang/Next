import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { CHART_SKILLS, chartChoicePrompt } from "./skills.ts";
import { buildChartTools } from "./charts.ts";
import { buildTools } from "./tools.ts";
import { NumberLedger } from "./ledger.ts";
import type { Ctx } from "./sources.ts";

Deno.test("workflow exposes the complete chart catalog for model selection", () => {
  const ctx = { db: {}, userId: "u", dayKey: "2026-09-05", tz: "UTC" } as Ctx;
  const tools = buildChartTools(ctx, new NumberLedger(), () => {});
  assertEquals(
    Object.keys(tools).sort(),
    CHART_SKILLS.map((skill) => `screen.render.${skill.type}`).sort(),
  );
  for (const locale of [true, false]) {
    const prompt = chartChoicePrompt(locale);
    for (const skill of CHART_SKILLS) assert(prompt.includes(skill.type));
  }
});

Deno.test("business read tools do not expose historical screen frames as data", () => {
  const db = {} as Ctx["db"];
  const tools = buildTools(db, "u", new NumberLedger());
  assertEquals("screen.last" in tools, false);
  assert("data.catalog" in tools);
  assert("data.read" in tools);
});
