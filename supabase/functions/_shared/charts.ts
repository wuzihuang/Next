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
import { fetchAs, sourceList, SOURCE_IDS, type ChartData, type Ctx, type Kind, type SourceResult } from "./sources.ts";
import type { NumberLedger } from "./ledger.ts";

const FAMILY_KIND: Record<ChartSkill["family"], Kind> = {
  number: "rows", curve: "curve", pair: "pair", column: "column", arc: "arc",
  gauge: "gauge", stack: "stack", grid: "grid", strip: "strip", rows: "rows",
  // 2026-09-06 gap audit · four shapes the first ten families could not hold.
  meter: "meter", scatter: "scatter", verdict: "verdict", trace: "trace",
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
    // ⚠️ Every one of these lines is serialized into all 33 render tools and re-sent on
    // every model step: the render step's schema payload measured 44k characters, and each
    // step was costing 15 s. The rules live in the system prompt (S3, S5, S11); the slot
    // descriptions here only name the cap.
    // ⚠️ Loose on purpose (2026-09-09): `"to": null` in a claim threw AI_InvalidToolArgumentsError
    // and killed a turn whose phone write had already succeeded. Shape is checked in execute().
    claims: z.any().optional().describe("Measured claims: [{id, metric, unit, from, to, value}] citing this turn's evidence id, metric, unit, range, value."),
    // ⚠️ Optional in the schema, required in execute(). Seen on production: the model left
    // `title` out of screen.render.food and the SDK threw AI_InvalidToolArgumentsError,
    // which kills the whole turn — the panel fell to the battery frame over a missing word.
    // A missing slot has to come back as a tool result the model can act on, never as a throw.
    title: z.string().optional().describe(en ? "Required, ≤ 18 chars: METRIC · WINDOW" : "必填，≤ 18 字：指标 · 窗口"),
    tag: z.string().optional().describe(TAGS.join("/")),
    sentence: z.string().optional().describe(en ? "Required, ≤ 48 chars; numbers only from this turn's tools" : "必填，≤ 48 字；数字只能来自本轮工具"),
    footer: z.string().optional().describe(en ? "≤ 42 chars, joined by ' · '" : "≤ 42 字，用 ' · ' 连"),
    action: z.string().optional().describe(en ? "≤ 32 chars, only for a real next step" : "≤ 32 字，只在真有下一步时写"),
    hero: z.string().optional().describe(en ? "≤ 16 chars, the big number; omit to use the source's" : "≤ 16 字大字；省略则用数据源自己的"),
    target: z.string().optional().describe(TARGETS.join("/")),
  };
}

export type Rendered = { rendered: true; type: string; hero?: string } | { rendered: false; error: "NO_DATA" | "QUERY_FAILED" | "INVALID_EVIDENCE" | "MISSING_TEXT"; say: string };

export function buildChartTools(ctx: Ctx, ledger: NumberLedger, onRender: (env: Envelope) => void,
                                locale = "en-US") {
  const tools: Record<string, Tool> = {};
  const words = wordsFor(locale);
  const en = locale.startsWith("en");

  for (const skill of CHART_SKILLS) {
    const skillSources = skill.sources;
    const kind = FAMILY_KIND[skill.family];
    const params = skillSources.length
      ? z.object({ ...words, source: z.string().describe(`${en ? "Data source, one of:" : "数据源，只取下面之一："}\n${sourceList(skillSources)}`) })
      : literalSchema(skill, words);

    tools[`screen.render.${skill.type}`] = tool({
      description: toolDescription(skill),
      parameters: params,
      // deno-lint-ignore no-explicit-any
      execute: async (args: any): Promise<Rendered> => {
        // The two slots the envelope cannot do without. Asking for them back costs one
        // model step; throwing costs the whole turn.
        const missing = ["title", "sentence"].filter((k) => !words_(args[k]));
        if (missing.length) {
          return { rendered: false, error: "MISSING_TEXT",
            say: `${missing.join(" and ")} ${missing.length > 1 ? "are" : "is"} required on every chart. Call this tool again with ${missing.join(" and ")} filled in.` };
        }
        let data: Record<string, unknown>;
        let hero: string | undefined = args.hero;
        if (skillSources.length) {
          if (!skillSources.includes(String(args.source))) {
            return { rendered: false, error: "NO_DATA", say: `${args.source} is not a source for this chart. Use one of: ${skillSources.join(", ")}.` };
          }
          let r: SourceResult | null;
          try { r = await fetchAs(args.source, kind, ctx); } catch {
            return { rendered:false, error:"QUERY_FAILED", say:"Source query failed. Do not describe this as no measurements; explain that data could not be loaded." };
          }
          if (!r) {
            return { rendered: false, error: "NO_DATA", say: `${args.source} has no data. Pick another source or another chart; if none fits, use screen.render.text and write —— for the missing number.` };
          }
          if (r.evidence) {
            const evidence = r.evidence as unknown as import("./ledger.ts").MeasurementEvidence;
            ledger.registerEvidence(evidence, {agg:r.agg,data:r.data,hero:numbersIn(r.hero)});
            if (args.hero && numbersIn(args.hero).some(value=>!ledger.hasClaim({...evidence,value}))) {
              return {rendered:false,error:"INVALID_EVIDENCE",say:"The hero value is not supported by this source snapshot. Omit hero to use the server value."};
            }
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
        const claims = normalizeClaims(args.claims);
        if (claims.some((claim)=>!ledger.hasClaim(claim))) {
          return {rendered:false,error:"INVALID_EVIDENCE",say:"A measured claim does not match the cited current metric, unit, interval, revision or value. Read the correct evidence and retry."};
        }

        if (hero) data.hero = hero;

        const tag = (TAGS as readonly string[]).includes(String(args.tag)) ? args.tag as (typeof TAGS)[number] : undefined;
        const target = (TARGETS as readonly string[]).includes(String(args.target)) ? args.target as (typeof TARGETS)[number] : skill.target;
        onRender({
          type: skill.type,
          title: words_(args.title) ?? "", tag, sentence: words_(args.sentence) ?? "",
          footer: words_(args.footer), action: words_(args.action),
          target,
          data, ttl_min: 20, priority: "normal", locale: en ? "en-US" : "zh-CN",
        });
        return { rendered: true, type: skill.type, hero };
      },
    });
  }
  return tools;
}

/// A claim list the model wrote as an array, as JSON text, or with nulls where strings go.
/// Anything that is not a claim-shaped object is dropped rather than thrown.
function normalizeClaims(raw: unknown): import("./ledger.ts").MeasurementClaim[] {
  let value: unknown = raw;
  if (typeof value === "string") { try { value = JSON.parse(value); } catch { return []; } }
  if (!Array.isArray(value)) return [];
  return value.slice(0, 32).flatMap((c) => {
    if (!c || typeof c !== "object") return [];
    const o = c as Record<string, unknown>;
    const n = Number(o.value);
    if (!Number.isFinite(n) || typeof o.id !== "string" || typeof o.metric !== "string") return [];
    return [{ id: o.id, metric: o.metric, unit: o.unit == null ? null : String(o.unit),
      from: o.from == null ? null : String(o.from), to: o.to == null ? String(o.from ?? "") : String(o.to), value: n }];
  });
}

/// Charts that carry no series: the model writes the value it read.
function literalSchema(skill: ChartSkill, words: ReturnType<typeof wordsFor>) {
  switch (skill.type) {
    // 07 · rule 6 · text has its own skeleton and no sentence slot on screen: an eyebrow,
    // one lime headline (the only highlight on the panel) and a sub under it. `sentence` is
    // still required by the envelope, and the panel uses it for the facts line.
    case "text":
      return z.object({
        ...words,
        headline: z.string().optional().describe("≤ 12 characters, the one big word on the panel; falls back to title"),
        eyebrow: z.string().optional().describe("the line above the headline, e.g. 'BATTERY 86% · TARGET 14.5'"),
        sub: z.string().optional().describe("the line under the headline, e.g. 'STRENGTH · 45 MIN'"),
      });
    // 07 · 20 · food is the plate: its name, the kcal as the hero, and the three macros
    // as their own rows. Never invent a number here — kcal and grams come from a tool.
    case "food":
      return z.object({
        ...words,
        name: z.string().describe("The dish"),
        portion: z.string().optional().describe("Portion, e.g. 'one bowl'"),
        // ⚠️ coerce, don't reject: qwen sends {"kcal":"350"} about as often as {"kcal":350},
        // and a strict z.number() there threw AI_InvalidToolArgumentsError and killed the turn.
        kcal: z.coerce.number().optional().describe("kcal, only if a tool returned it"),
        protein_g: z.coerce.number().optional(),
        carb_g: z.coerce.number().optional(),
        fat_g: z.coerce.number().optional(),
        pct_of_budget: z.coerce.number().optional().describe("share of today's target, only if computed"),
      });
    case "metric":
      return z.object({
        ...words,
        value: z.coerce.string().describe("The number, straight from a tool return this turn, e.g. '72'"),
        unit: z.string().optional().describe("Unit, e.g. 'bpm'"),
        label: z.string().optional().describe("Metric name; overrides title"),
        ref: z.string().optional().describe("Reference, e.g. '+4 VS RHR 52'"),
      });
    default:
      return z.object({ ...words });
  }
}

// deno-lint-ignore no-explicit-any
function literalData(skill: ChartSkill, a: any): Record<string, unknown> {
  switch (skill.type) {
    case "metric":
      // "32 %" reads as two tokens; a percent sign sits on its number.
      return { hero: [a.value, a.unit].filter(Boolean).join(String(a.unit).trim() === "%" ? "" : " "), value: a.value, unit: a.unit, label: a.label, ref: a.ref };
    // A text panel with no headline draws an empty highlight; the title is the honest
    // stand-in, which is what the tool-call repair already did before it could parse.
    case "text":
      return { headline: words_(a.headline) ?? words_(a.title), eyebrow: a.eyebrow, sub: a.sub };
    case "food":
      return {
        name: a.name, portion: a.portion, kcal: a.kcal,
        macros: { p: a.protein_g, c: a.carb_g, f: a.fat_g },
        pct_of_budget: a.pct_of_budget,
        rows: [{ label: [a.name, a.portion].filter(Boolean).join(" · "), value: a.kcal != null ? String(a.kcal) : "" }],
      };
    default:
      return {};
  }
}

/// The renderer's own keys, exactly as AIService.decodeData reads them.
function shape(d: ChartData): Record<string, unknown> {
  switch (d.kind) {
    case "curve":  return { series: d.series, ...(d.split != null ? { split: d.split } : {}),
                            ...(d.mark != null ? { mark: d.mark } : {}), ...(d.marks ? { marks: d.marks } : {}) };
    case "pair":   return { hi: d.hi, lo: d.lo, a: d.a, b: d.b };
    case "column": return { bins: d.bins, unit: d.unit, total: d.total };
    case "arc":    return { value: d.value, goal: d.goal, unit: d.unit };
    case "gauge":  return { value: d.value, zones: d.zones };
    case "stack":  return { parts: d.parts };
    case "grid":   return { rows: d.rows, cols: d.cols, cells: d.cells, scale: d.scale, rowLabels: d.rowLabels, colLabels: d.colLabels };
    case "strip":  return { minutes: d.minutes, current_zone: d.current_zone, lanes: d.lanes, from: d.from, to: d.to };
    case "rows":   return { rows: d.rows };
    case "meter":  return { value: d.value, max: d.max, parts: d.parts };
    case "scatter": return { points: d.points, lo: d.lo, hi: d.hi, stats: d.stats };
    case "verdict": return { word: d.word, options: d.options, confidence: d.confidence, steps: d.steps };
    case "trace":  return { samples: d.samples, hz: d.hz };
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
  if (d.kind === "meter") d.parts.forEach((p) => labels.push(p.label));
  if (d.kind === "scatter") d.stats.forEach((p) => labels.push(p.value));
  return labels.flatMap((l) => numbersIn(l));
}

/// ⚠️ Seen on production: a title came back as "READINESS</title>". Nothing in the prompt
/// asks for markup, and the tag-safe wrapper only guards the two prompt tags — a stray
/// closing tag in a text slot is just noise the model shed, and it would be printed on the
/// panel verbatim. Anything that looks like a tag is dropped from the four word slots.
function words_(v: unknown): string | undefined {
  if (v == null) return undefined;
  const out = String(v).replace(/<\/?[a-zA-Z][^>]*>/g, "").trim();
  return out.length ? out : undefined;
}

function numbersIn(s: string | undefined): number[] {
  if (!s) return [];
  return [...s.matchAll(/-?\d+(?:\.\d+)?/g)].map((m) => Number(m[0]));
}

export type { SourceResult };


/// The three literal charts keep their own tools (they are direct outputs in read/act and
/// carry their own fields); every source-backed chart is one tool, `screen.render`, that
/// takes `type` and `source`. 33 tools re-sent on every render step measured 32k characters
/// of schema; this is under 8k, and the chart rules already live in S11.
export const RENDER_TOOL = "screen.render";
export const LITERAL_TYPES = new Set(["text", "food", "metric"]);

export function buildRenderTools(ctx: Ctx, ledger: NumberLedger, onRender: (env: Envelope) => void,
                                 locale = "en-US"): Record<string, Tool> {
  const perChart = buildChartTools(ctx, ledger, onRender, locale);
  const en = locale.startsWith("en");
  const tools: Record<string, Tool> = {};
  for (const t of LITERAL_TYPES) tools[`screen.render.${t}`] = perChart[`screen.render.${t}`];
  const series = CHART_SKILLS.filter((s) => s.sources.length > 0);
  const typeLines = series.map((s) => `${s.type}: ${s.sources.join(", ")}`).join("\n");
  const usedSources = [...new Set(series.flatMap((s) => s.sources))].filter((id) => SOURCE_IDS.includes(id));
  tools[RENDER_TOOL] = tool({
    description: (en
      ? `Draw one series chart from a server-filled source. type is one of ${series.map((s) => s.type).join(" / ")} (rules in S11); source must be one of the type's sources below. The server reads the rows and returns NO_DATA when there are none — then pick another source or type, or use screen.render.text with ——.\nTYPE → SOURCES\n`
      : `画一张由服务端填数据的序列图。type 取 ${series.map((s) => s.type).join(" / ")} 之一（规则见 S11）；source 必须是该 type 下列出的数据源之一。服务端读行，没有数据时返回 NO_DATA——那就换 source 或换图，或用 screen.render.text 写 ——。\nTYPE → SOURCES\n`)
      + typeLines + "\n" + (en ? "SOURCES\n" : "数据源\n") + sourceList(usedSources),
    parameters: z.object({
      ...wordsFor(locale),
      type: z.string().describe(en ? "chart type" : "图的类型"),
      source: z.string().optional().describe(en ? "data source id for that type" : "该类型允许的数据源 id"),
    }),
    // deno-lint-ignore no-explicit-any
    execute: async (args: any, opts: any): Promise<Rendered> => {
      const raw = String(args?.type ?? "").trim().toLowerCase().replace(/^screen\.render\./, "");
      const skill = CHART_SKILLS.find((s) => s.type.toLowerCase() === raw);
      if (!skill) {
        return { rendered: false, error: "NO_DATA", say: `"${args?.type}" is not a chart type. Use one of: ${series.map((s) => s.type).join(", ")} (or screen.render.text / food / metric).` };
      }
      const target = perChart[`screen.render.${skill.type}`];
      if (!target?.execute) return { rendered: false, error: "NO_DATA", say: "That chart is unavailable." };
      if (skill.sources.length && !args?.source) {
        return { rendered: false, error: "NO_DATA", say: `${skill.type} needs a source: one of ${skill.sources.join(", ")}.` };
      }
      return await target.execute(args, opts) as Rendered;
    },
  });
  return tools;
}
