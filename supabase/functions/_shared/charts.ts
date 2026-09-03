// 07 · 02 · the render tools, one per chart.
//
// F4 §01 · the vocabulary stays, the transport is cut: every widget on board 07 is a tool
// named screen.render.<type>, defined here with tool() + Zod inside the Edge Function. The
// model chooses a chart and a data source and writes the four text slots; the server reads
// the rows, shapes the data exactly as the renderer eats it, and returns the envelope.
//
// Why per-chart tools rather than one screen.render with a free `data`: a small model
// given 27 shapes in one description invented its own keys and the panel drew an empty
// box. Given one flat, strict schema per chart it fills the schema. And the series never
// crosses the wire twice — the model names the source, the server draws it.

import { tool, type Tool } from "npm:ai@4.3.16";
import { z } from "npm:zod@3.25.76";
import { CHART_SKILLS, toolDescription, type ChartSkill } from "./skills.ts";
import { TARGETS, type Envelope } from "./contract.ts";
import { fetchAs, sourceList, type ChartData, type Ctx, type Kind, type SourceResult } from "./sources.ts";
import type { NumberLedger } from "./ledger.ts";

const FAMILY_KIND: Record<ChartSkill["family"], Kind> = {
  number: "rows", curve: "curve", pair: "pair", column: "column", arc: "arc",
  gauge: "gauge", stack: "stack", grid: "grid", strip: "strip", rows: "rows",
};

/// The four text slots, plus target and hero. Same on every chart.
///
/// ⚠️ `tag`, `target` and `source` are strings here, not enums, on purpose. Seen on
/// production: the model left `target` out once, the Zod enum failed inside generateText,
/// AI_InvalidToolArgumentsError threw, and the whole turn came back MODEL_UNAVAILABLE with
/// an empty tool trace — the panel fell to the battery frame over one missing word. The
/// allowed values live in the descriptions and are checked in execute(): a wrong one is a
/// tool result the model can act on, a missing target is the skill's own.
const TAGS = ["MOVE", "FUEL", "RECOVER", "ALERT"] as const;
/// 11 · 07 · the words follow the app's language. The slot descriptions are written in it
/// too: a model reads the language of its instructions as the language it should answer in.
function wordsFor(locale: string) {
  const en = locale.startsWith("en");
  return {
    title: z.string().describe(en ? "≤ 18 characters, upper-cased on screen; 'METRIC · WINDOW'" : "≤ 18 个字符，屏上会转大写；写「指标 · 窗口」"),
    tag: z.string().optional().describe(en ? `One of ${TAGS.join(" / ")}, optional` : `只取 ${TAGS.join(" / ")} 之一，可省略`),
    sentence: z.string().describe(en ? "≤ 48 characters, two lines at most, required, in English; every number comes from a tool return this turn" : "≤ 48 字，两行封顶，必填；数字必须来自本轮读到的值"),
    footer: z.string().optional().describe(en ? "≤ 42 characters, segments joined by ' · ', in English" : "≤ 42 字，几段用 ' · ' 连"),
    action: z.string().optional().describe(en ? "≤ 32 characters, only when there is a real next step" : "≤ 32 字，只在真有下一步时写"),
    hero: z.string().optional().describe(en ? "≤ 16 characters, the big number; omit to use the source's own" : "≤ 16 字的大字；省略则服务端用数据源自己的"),
    target: z.string().optional().describe(en ? `The page a tap opens, one of ${TARGETS.join(" / ")}` : `点击落到哪一页，只取 ${TARGETS.join(" / ")} 之一`),
  };
}

export type Rendered = { rendered: true; type: string; hero?: string } | { rendered: false; error: "NO_DATA"; say: string };

export function buildChartTools(ctx: Ctx, ledger: NumberLedger, onRender: (env: Envelope) => void, locale = "en-US") {
  const tools: Record<string, Tool> = {};
  const words = wordsFor(locale);
  const en = locale.startsWith("en");

  for (const skill of CHART_SKILLS) {
    const kind = FAMILY_KIND[skill.family];
    const params = skill.sources.length
      ? z.object({ ...words, source: z.string().describe(`${en ? "Data source, one of:" : "数据源，只取下面之一："}\n${sourceList(skill.sources)}`) })
      : literalSchema(skill, words);

    tools[`screen.render.${skill.type}`] = tool({
      description: toolDescription(skill),
      parameters: params,
      // deno-lint-ignore no-explicit-any
      execute: async (args: any): Promise<Rendered> => {
        let data: Record<string, unknown>;
        let hero: string | undefined = args.hero;
        if (skill.sources.length) {
          if (!skill.sources.includes(String(args.source))) {
            return { rendered: false, error: "NO_DATA", say: `${args.source} is not a source for this chart. Use one of: ${skill.sources.join(", ")}.` };
          }
          const r = await fetchAs(args.source, kind, ctx);
          if (!r) {
            return { rendered: false, error: "NO_DATA", say: `${args.source} has no data. Pick another source or another chart; if none fits, use screen.render.text and write —— for the missing number.` };
          }
          data = shape(r.data);
          hero = hero ?? r.hero;
          // The numbers the model may say about this chart are the chart's own facts —
          // they enter the ledger the way a read tool's return does.
          ledger.harvest(r.agg, `${skill.type}.${args.source}`);
          ledger.harvest(numbersIn(r.hero), `${skill.type}.hero`);
          // The axis is a fact about the data too: "the 18:00 bin", "Saturday 18–20". A
          // caption that names a label's number was being thrown away over it.
          ledger.harvest(axisNumbers(r.data), `${skill.type}.axis`);
          if (r.data.kind === "rows") {
            ledger.harvest(r.data.rows.map((x) => numbersIn(x.value)), `${skill.type}.rows`);
            ledger.add(r.data.rows.length, `${skill.type}.rows.length`);
          }
          if (r.window) data.window = r.window;
          if (r.unit) data.unit = r.unit;
        } else {
          data = literalData(skill, args);
        }
        if (hero) data.hero = hero;

        const tag = (TAGS as readonly string[]).includes(String(args.tag)) ? args.tag as (typeof TAGS)[number] : undefined;
        const target = (TARGETS as readonly string[]).includes(String(args.target)) ? args.target as (typeof TARGETS)[number] : skill.target;
        onRender({
          type: skill.type,
          title: String(args.title ?? ""), tag, sentence: String(args.sentence ?? ""), footer: args.footer, action: args.action,
          target,
          data, ttl_min: 20, priority: "normal", locale: en ? "en-US" : "zh-CN",
        });
        return { rendered: true, type: skill.type, hero };
      },
    });
  }
  return tools;
}

/// Charts that carry no series: the model writes the value it read.
function literalSchema(skill: ChartSkill, words: ReturnType<typeof wordsFor>) {
  switch (skill.type) {
    case "metric":
      return z.object({
        ...words,
        value: z.string().describe("The number, straight from a tool return this turn, e.g. '72'"),
        unit: z.string().optional().describe("Unit, e.g. 'bpm'"),
        label: z.string().optional().describe("Metric name; overrides title"),
        ref: z.string().optional().describe("Reference, e.g. '+4 VS RHR 52'"),
      });
    case "food":
      return z.object({
        ...words,
        name: z.string().describe("The dish"),
        portion: z.string().optional().describe("Portion, e.g. 'half a bowl'"),
      });
    default:
      return z.object({ ...words });
  }
}

// deno-lint-ignore no-explicit-any
function literalData(skill: ChartSkill, a: any): Record<string, unknown> {
  switch (skill.type) {
    case "metric":
      return { hero: [a.value, a.unit].filter(Boolean).join(" "), value: a.value, unit: a.unit, label: a.label, ref: a.ref };
    case "food":
      return { rows: [{ label: [a.name, a.portion].filter(Boolean).join(" · "), value: "" }], name: a.name, portion: a.portion };
    default:
      return {};
  }
}

/// The renderer's own keys, exactly as AIService.decodeData reads them.
function shape(d: ChartData): Record<string, unknown> {
  switch (d.kind) {
    case "curve":  return { series: d.series, ...(d.split != null ? { split: d.split } : {}) };
    case "pair":   return { hi: d.hi, lo: d.lo, a: d.a, b: d.b };
    case "column": return { bins: d.bins, unit: d.unit, total: d.total };
    case "arc":    return { value: d.value, goal: d.goal, unit: d.unit };
    case "gauge":  return { value: d.value, zones: d.zones };
    case "stack":  return { parts: d.parts };
    case "grid":   return { rows: d.rows, cols: d.cols, cells: d.cells, scale: d.scale, rowLabels: d.rowLabels, colLabels: d.colLabels };
    case "strip":  return { minutes: d.minutes, current_zone: d.current_zone, lanes: d.lanes, from: d.from, to: d.to };
    case "rows":   return { rows: d.rows };
  }
}

function axisNumbers(d: ChartData): number[] {
  const labels: string[] = [];
  const take = (pts?: [string, number][]) => pts?.forEach((p) => labels.push(p[0]));
  if (d.kind === "curve") take(d.series);
  if (d.kind === "column") take(d.bins);
  if (d.kind === "pair") { take(d.hi); take(d.lo); }
  if (d.kind === "stack") take(d.parts);
  if (d.kind === "grid") { d.colLabels?.forEach((l) => labels.push(l)); d.rowLabels?.forEach((l) => labels.push(l)); }
  if (d.kind === "rows") d.rows.forEach((r) => labels.push(r.label));
  return labels.flatMap((l) => numbersIn(l));
}

function numbersIn(s: string | undefined): number[] {
  if (!s) return [];
  return [...s.matchAll(/-?\d+(?:\.\d+)?/g)].map((m) => Number(m[0]));
}

export type { SourceResult };
