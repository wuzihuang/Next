import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { CHART_SKILLS, chartChoicePrompt } from "./skills.ts";
import { buildChartTools, buildRenderTools } from "./charts.ts";
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

Deno.test("the render surface is one chart tool plus the three literal charts, and type dispatches", async () => {
  const ctx = { db: {}, userId: "u", dayKey: "2026-09-05", tz: "UTC" } as Ctx;
  const tools = buildRenderTools(ctx, new NumberLedger(), () => {});
  assertEquals(Object.keys(tools).sort(), ["screen.render", "screen.render.food", "screen.render.metric", "screen.render.text"]);
  const description = String(tools["screen.render"].description);
  for (const skill of CHART_SKILLS.filter((s) => s.sources.length)) assert(description.includes(`${skill.type}: `), skill.type);
  assert(description.length < 6000, `description is ${description.length} chars`);
  const bad = await tools["screen.render"].execute!({ type: "pie", title: "T", sentence: "S" }, {} as never) as { rendered: boolean; say: string };
  assertEquals(bad.rendered, false);
  assert(bad.say.includes("line"));
  const noSource = await tools["screen.render"].execute!({ type: "line", title: "T", sentence: "S" }, {} as never) as { rendered: boolean; say: string };
  assertEquals(noSource.rendered, false);
  assert(noSource.say.includes("heart.today"));
});

Deno.test("business read tools do not expose historical screen frames as data", () => {
  const db = {} as Ctx["db"];
  const tools = buildTools(db, "u", new NumberLedger());
  assertEquals("screen.last" in tools, false);
  assertEquals(Object.keys(tools).sort(), ["find", "read"]);
});
