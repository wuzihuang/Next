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
const words = {
  title: z.string().describe("≤ 18 个字符，屏上会转大写；写「指标 · 窗口」"),
  tag: z.enum(["MOVE", "FUEL", "RECOVER", "ALERT"]).optional(),
  sentence: z.string().describe("≤ 48 字，两行封顶，必填；数字必须来自本轮读到的值"),
  footer: z.string().optional().describe("≤ 42 字，几段用 ' · ' 连"),
  action: z.string().optional().describe("≤ 32 字，只在真有下一步时写"),
  hero: z.string().optional().describe("≤ 16 字的大字；省略则服务端用数据源自己的"),
  target: z.enum(TARGETS).describe("点击落到哪一页"),
};

export type Rendered = { rendered: true; type: string; hero?: string } | { rendered: false; error: "NO_DATA"; say: string };

export function buildChartTools(ctx: Ctx, ledger: NumberLedger, onRender: (env: Envelope) => void) {
  const tools: Record<string, Tool> = {};

  for (const skill of CHART_SKILLS) {
    const kind = FAMILY_KIND[skill.family];
    const params = skill.sources.length
      ? z.object({ ...words, source: z.enum(skill.sources as [string, ...string[]]).describe(`数据源：\n${sourceList(skill.sources)}`) })
      : literalSchema(skill);

    tools[`screen.render.${skill.type}`] = tool({
      description: toolDescription(skill),
      parameters: params,
      // deno-lint-ignore no-explicit-any
      execute: async (args: any): Promise<Rendered> => {
        let data: Record<string, unknown>;
        let hero: string | undefined = args.hero;
        if (skill.sources.length) {
          const r = await fetchAs(args.source, kind, ctx);
          if (!r) {
            return { rendered: false, error: "NO_DATA", say: `${args.source} 今天是空的。换一个数据源或另一种图；没有图配得上就用 screen.render.text，把缺的数写成 ——。` };
          }
          data = shape(r.data);
          hero = hero ?? r.hero;
          // The numbers the model may say about this chart are the chart's own facts —
          // they enter the ledger the way a read tool's return does.
          ledger.harvest(r.agg, `${skill.type}.${args.source}`);
          ledger.harvest(numbersIn(r.hero), `${skill.type}.hero`);
          if (r.data.kind === "rows") ledger.harvest(r.data.rows.map((x) => numbersIn(x.value)), `${skill.type}.rows`);
          if (r.window) data.window = r.window;
          if (r.unit) data.unit = r.unit;
        } else {
          data = literalData(skill, args);
        }
        if (hero) data.hero = hero;

        onRender({
          type: skill.type,
          title: args.title, tag: args.tag, sentence: args.sentence, footer: args.footer, action: args.action,
          target: args.target ?? skill.target,
          data, ttl_min: 20, priority: "normal", locale: "zh-CN",
        });
        return { rendered: true, type: skill.type, hero };
      },
    });
  }
  return tools;
}

/// Charts that carry no series: the model writes the value it read.
function literalSchema(skill: ChartSkill) {
  switch (skill.type) {
    case "metric":
      return z.object({
        ...words,
        value: z.string().describe("数值，来自本轮读到的值，如 '72'"),
        unit: z.string().optional().describe("单位，如 'bpm'"),
        label: z.string().optional().describe("指标名，压过 title"),
        ref: z.string().optional().describe("参照，如 '+4 VS RHR 52'"),
      });
    case "food":
      return z.object({
        ...words,
        name: z.string().describe("菜名"),
        portion: z.string().optional().describe("份量，如 '半碗'"),
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
    case "strip":  return { minutes: d.minutes, current_zone: d.current_zone };
    case "rows":   return { rows: d.rows };
  }
}

function numbersIn(s: string | undefined): number[] {
  if (!s) return [];
  return [...s.matchAll(/-?\d+(?:\.\d+)?/g)].map((m) => Number(m[0]));
}

export type { SourceResult };
