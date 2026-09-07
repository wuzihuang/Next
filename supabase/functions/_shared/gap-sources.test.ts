// 2026-09-06 gap audit · the six new panel types and the trace that finally gives `wave` a
// source. Two things are being held down here:
//
//   · the catalogue is closed — every PANEL_TYPE has exactly one render tool, every skill
//     names sources that exist, and every source hands back the kind its family asks for.
//     The counting is the part that went wrong last time (a 28th type nobody had a tool
//     for), so it is a test rather than a note.
//   · each new source actually reads its rows and shapes them the way AIService decodes
//     them — with the null case checked, because a source that returns 0 for "not measured"
//     is the failure that puts a wrong number on the panel.

import { assertEquals, assertExists } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { PANEL_TYPES } from "./contract.ts";
import { CHART_SKILLS, SKILL_BY_TYPE } from "./skills.ts";
import { type ChartData, type Ctx, fetchAs, SOURCE_BY_ID, SOURCE_IDS } from "./sources.ts";

const FAMILY_KIND: Record<string, string> = {
  number: "rows", curve: "curve", pair: "pair", column: "column", arc: "arc",
  gauge: "gauge", stack: "stack", grid: "grid", strip: "strip", rows: "rows",
  meter: "meter", scatter: "scatter", verdict: "verdict", trace: "trace",
};

// ---------------------------------------------------------------- the catalogue is closed

Deno.test("every panel type has exactly one render tool", () => {
  // `plan` is the one type whose tool is not screen.render.*: it is plan.render, built in
  // plan.ts and only registered on the plan surface. Everything else is a chart skill.
  const withoutSkill = PANEL_TYPES.filter((t) => t !== "plan" && !SKILL_BY_TYPE.has(t));
  assertEquals(withoutSkill, []);
  assertEquals(CHART_SKILLS.length, PANEL_TYPES.length - 1);
  const types = CHART_SKILLS.map((s) => s.type);
  assertEquals(new Set(types).size, types.length, "a type is claimed by two skills");
});

Deno.test("every skill names sources that exist and shapes it can eat", () => {
  const ids = new Set<string>(SOURCE_IDS);
  const convertible = (from: string, to: string) =>
    from === to || (from === "curve" && to === "column") || (from === "column" && to === "curve");
  for (const skill of CHART_SKILLS) {
    for (const id of skill.sources) {
      assertEquals(ids.has(id), true, `${skill.type} names a missing source ${id}`);
      const kind = SOURCE_BY_ID.get(id)!.kind;
      assertEquals(
        convertible(kind, FAMILY_KIND[skill.family]),
        true,
        `${skill.type} (${skill.family} → ${FAMILY_KIND[skill.family]}) cannot draw ${id} (${kind})`,
      );
    }
  }
});

Deno.test("the six audited types are wired end to end", () => {
  for (const [type, source] of [
    ["score", "sleep.score.night"], ["poincare", "balance.check.last"],
    ["matrix", "sync.status.7d"], ["call", "composition.call"],
    ["curve", "load.curve.today"], ["response", "response.meal.last"],
    ["wave", "rr.tachogram.last"],
  ] as const) {
    const skill = SKILL_BY_TYPE.get(type);
    assertExists(skill, `${type} has no skill`);
    assertEquals(skill!.sources.includes(source), true, `${type} does not name ${source}`);
  }
});

// ---------------------------------------------------------------- the sources read rows

/// A Supabase client that answers from a table map. Only the operators the new sources use
/// are implemented; anything else would be a silent pass, so it throws.
function client(tables: Record<string, Record<string, unknown>[]>) {
  return {
    rpc: () => Promise.resolve({ data: [], error: null }),
    from(table: string) {
      let rows = [...(tables[table] ?? [])];
      const q = {
        select: () => q,
        eq(k: string, v: unknown) {
          if (k !== "user_id") rows = rows.filter((r) => r[k] === v);
          return q;
        },
        not(k: string, op: string, _v: unknown) {
          if (op !== "is") throw new Error(`unsupported not(${op})`);
          rows = rows.filter((r) => r[k] != null);
          return q;
        },
        gte(k: string, v: string) { rows = rows.filter((r) => String(r[k]) >= v); return q; },
        gt(k: string, v: string) { rows = rows.filter((r) => String(r[k]) > v); return q; },
        lte(k: string, v: string) { rows = rows.filter((r) => String(r[k]) <= v); return q; },
        lt(k: string, v: string) { rows = rows.filter((r) => String(r[k]) < v); return q; },
        order(k: string, opts?: { ascending?: boolean }) {
          const dir = opts?.ascending === false ? -1 : 1;
          rows.sort((a, b) => (String(a[k]) < String(b[k]) ? -1 : String(a[k]) > String(b[k]) ? 1 : 0) * dir);
          return q;
        },
        limit(n: number) { rows = rows.slice(0, n); return { ...q, ...settled() }; },
        range: () => ({ ...q, ...settled() }),
        then<T>(res: (v: { data: unknown[]; error: null }) => T) { return Promise.resolve(res(settled())); },
      };
      const settled = () => ({ data: rows, error: null as null });
      return q;
    },
  };
}

function ctx(tables: Record<string, Record<string, unknown>[]>): Ctx {
  return {
    db: client(tables) as unknown as Ctx["db"],
    userId: "u", dayKey: "2026-09-06", tz: "UTC", cache: new Map(),
  };
}

async function read(id: string, tables: Record<string, Record<string, unknown>[]>) {
  const kind = SOURCE_BY_ID.get(id)!.kind;
  return await fetchAs(id, kind, ctx(tables));
}

Deno.test("sleep.score.night keeps the total and drops sub-scores that were not computed", async () => {
  const r = await read("sleep.score.night", {
    night_score: [{
      user_day: "2026-09-06", score: 73, duration_score: 78, architecture_score: 61,
      recovery_score: 84, regularity_score: null,
    }],
  });
  assertExists(r);
  const d = r!.data as Extract<ChartData, { kind: "meter" }>;
  assertEquals(d.kind, "meter");
  assertEquals(d.value, 73);
  // regularity was never computed: it is absent, not a zero bar.
  assertEquals(d.parts.map((p) => p.label), ["DURATION", "ARCHITECTURE", "RECOVERY"]);
  assertEquals(r!.agg.worst, 61);
  assertEquals(r!.hero, "73");
});

Deno.test("sleep.score.night is null when the night was never scored", async () => {
  assertEquals(await read("sleep.score.night", { night_score: [] }), null);
});

/// The band writes one HRV sample per row — a handful of intervals each — so a reading is a
/// run of rows. Reading only the newest row is how this shipped returning NULL against real
/// rows that plainly had a cloud in them.
function rrRows(minutes: number[], per = 8): Record<string, unknown>[] {
  return minutes.map((m) => ({
    ts: `2026-09-06T08:${String(m).padStart(2, "0")}:00Z`,
    rr_ms: Array.from({ length: per }, (_, i) => 780 + (i % 5) * 12),
  }));
}

Deno.test("balance.check.last gathers the whole run of rows, not just the newest", async () => {
  const tables = {
    balance_checks: [{
      measured_at: "2026-09-06T09:00:00Z", lead: "rest", rest_share: 64,
      sd1_ms: 31.5, sd2_ms: 62.1, sdnn_ms: 48.2, heart_rate: 62, beat_count: 41,
      algo_version: "poincare-1",
    }],
    // Four rows inside the ten-minute window, one long before it.
    band_rr_evidence: rrRows([12, 55, 56, 57, 58]),
  };
  const r = await read("balance.check.last", tables);
  assertExists(r);
  const d = r!.data as Extract<ChartData, { kind: "scatter" }>;
  // 4 rows × 8 intervals = 32 beats → 31 pairs. The 08:12 row is out of the window.
  assertEquals(d.points.length, 31);
  assertEquals(r!.hero, "48 ms");
  assertEquals(r!.window, "REST");
  assertEquals(r!.agg.pairs, 31);
  // The cloud travels with its readings: a shape with no numbers beside it is not a reading.
  assertEquals(d.stats, [
    { label: "SDNN", value: "48 ms" },
    { label: "LEAD", value: "REST" },
    { label: "REST SHARE", value: "64 %" },
  ]);
});

Deno.test("balance.check.last refuses a reading under the twelve-interval floor", async () => {
  const tables = {
    balance_checks: [{
      measured_at: "2026-09-06T09:00:00Z", lead: "rest", rest_share: 64,
      sd1_ms: 31.5, sd2_ms: 62.1, sdnn_ms: 48.2, heart_rate: 62, beat_count: 41,
      algo_version: "poincare-1",
    }],
    band_rr_evidence: rrRows([58], 4),
  };
  assertEquals(await read("balance.check.last", tables), null);
});

Deno.test("intervals outside the physiological range are dropped, not drawn", async () => {
  // 2400 ms is 25 bpm and 120 ms is 500 bpm: dropped or doubled beats, and one of them in a
  // forty-second series moves SD1 more than the wearer's own state does.
  const r = await read("rr.tachogram.last", {
    band_rr_evidence: [{
      ts: "2026-09-06T08:58:00Z",
      rr_ms: [...Array.from({ length: 20 }, () => 800), 2400, 120, 0],
    }],
  });
  assertExists(r);
  const d = r!.data as Extract<ChartData, { kind: "trace" }>;
  assertEquals(d.samples.length, 20);
});

Deno.test("sync.status.7d keeps the five states apart and never calls a gap a zero day", async () => {
  const r = await read("sync.status.7d", {
    sync_domain_status: [
      { user_day: "2026-09-06", domain: "heart", status: "complete" },
      { user_day: "2026-09-06", domain: "sleep", status: "partial" },
      { user_day: "2026-09-05", domain: "sleep", status: "failed" },
      { user_day: "2026-09-04", domain: "body", status: "unsupported" },
    ],
  });
  assertExists(r);
  const d = r!.data as Extract<ChartData, { kind: "grid" }>;
  assertEquals(d.rows, 3);
  assertEquals(d.cols, 7);
  assertEquals(d.rowLabels, ["BODY", "HEART", "SLEEP"]);
  assertEquals(r!.agg.complete, 1);
  assertEquals(r!.agg.partial, 1);
  assertEquals(r!.agg.failed, 1);
  assertEquals(r!.agg.unsupported, 1);
  // The days nothing was attempted are "not collected", which is state 0 and its own colour.
  assertEquals(r!.agg.missing, 17);
});

Deno.test("composition.call carries the confidence and what it rests on", async () => {
  const r = await read("composition.call", {
    daily_results: [
      { user_day: "2026-09-05", the_call: "RECOMP", the_call_confidence: "MEDIUM" },
      { user_day: "2026-09-01", the_call: "CUT", the_call_confidence: "HIGH" },
    ],
    weigh_ins: [
      { measured_at: "2026-09-02T07:00:00Z" }, { measured_at: "2026-09-03T07:00:00Z" },
      { measured_at: "2026-09-05T07:00:00Z" }, { measured_at: "2026-09-06T07:00:00Z" },
    ],
  });
  assertExists(r);
  const d = r!.data as Extract<ChartData, { kind: "verdict" }>;
  assertEquals(d.word, "RECOMP");
  assertEquals(d.confidence, 2);
  assertEquals(d.steps, 3);
  assertEquals(d.options.length, 5);
  assertEquals(r!.agg.weighIns, 4);
});

Deno.test("composition.call is null when nothing has been called yet", async () => {
  assertEquals(
    await read("composition.call", {
      daily_results: [{ user_day: "2026-09-05", the_call: null, the_call_confidence: null }],
      weigh_ins: [],
    }),
    null,
  );
});

Deno.test("load.curve.today draws the accumulation against its full value of 21", async () => {
  const base = Date.parse("2026-09-06T06:00:00Z") / 1000;
  // Two queries, not a nested join: `curve` is jsonb and dayRows' select leaves it out.
  const r = await read("load.curve.today", {
    daily_results: [{ id: "r1", user_day: "2026-09-06" }],
    daily_training: [{
      result_id: "r1", peak_hr: 178, zone_minutes: [22, 18, 12, 8, 3],
      curve: [[base, 0], [base + 300, 2.6], [base + 600, 9.2], [base + 900, 14.2]],
    }],
  });
  assertExists(r);
  const d = r!.data as Extract<ChartData, { kind: "curve" }>;
  assertEquals(d.mark, 21);
  assertEquals(d.series.length, 4);
  assertEquals(d.series[3][1], 14.2);
  assertEquals(r!.agg.hardMinutes, 11);
  assertEquals(r!.agg.peakHr, 178);
});

Deno.test("response.meal.last is an index over the meal's own baseline, with both marks", async () => {
  const at = Date.parse("2026-09-06T12:10:00Z");
  const min = (n: number) => new Date(at + n * 60_000).toISOString();
  const samples = [
    { ts: min(-20), optical: 100 }, { ts: min(-10), optical: 100 },
    { ts: min(0), optical: 101 }, { ts: min(20), optical: 124 },
    { ts: min(42), optical: 138 }, { ts: min(70), optical: 118 },
    { ts: min(100), optical: 104 }, { ts: min(115), optical: 100 },
  ];
  const r = await read("response.meal.last", {
    meals: [{ logged_at: min(0), slot: "lunch" }],
    response_samples: samples,
  });
  assertExists(r);
  const d = r!.data as Extract<ChartData, { kind: "curve" }>;
  // Baseline is the mean of the two pre-meal samples, so the peak is +38 and not 138.
  assertEquals(r!.hero, "+38");
  assertEquals(r!.agg.peak, 38);
  assertEquals(r!.agg.peakAfterMin, 42);
  // Settled is the first sample back inside the baseline band (+5), which is the 100-minute
  // sample at +4 — not the later one that happens to land exactly on 0.
  assertEquals(r!.agg.settleMin, 100);
  assertEquals(d.marks, [2, 6]);
  assertEquals(r!.window, "LUNCH");
});

Deno.test("response.meal.last finds the peak after the meal, never before it", async () => {
  // A quiet pre-meal sample used to win the search and print "peak at −86 min" against real
  // rows: a number that is not slightly wrong, it is describing the wrong event.
  const at = Date.parse("2026-09-06T12:10:00Z");
  const min = (n: number) => new Date(at + n * 60_000).toISOString();
  const r = await read("response.meal.last", {
    meals: [{ logged_at: min(0), slot: "snack" }],
    response_samples: [
      { ts: min(-80), optical: 140 },   // the highest sample in the window, and pre-meal
      { ts: min(-40), optical: 100 },
      { ts: min(30), optical: 108 },
      { ts: min(75), optical: 104 },
    ],
  });
  assertExists(r);
  assertEquals((r!.agg.peakAfterMin as number) > 0, true);
  assertEquals(r!.agg.peakAfterMin, 30);
});

Deno.test("response.meal.last refuses to guess without a pre-meal baseline", async () => {
  const at = Date.parse("2026-09-06T12:10:00Z");
  const min = (n: number) => new Date(at + n * 60_000).toISOString();
  assertEquals(
    await read("response.meal.last", {
      meals: [{ logged_at: min(0), slot: "lunch" }],
      response_samples: [0, 10, 20, 30, 40, 50].map((n) => ({ ts: min(n), optical: 110 + n })),
    }),
    null,
  );
});

Deno.test("rr.tachogram.last gives wave a real trace in milliseconds", async () => {
  const r = await read("rr.tachogram.last", { band_rr_evidence: rrRows([55, 56, 57, 58]) });
  assertExists(r);
  const d = r!.data as Extract<ChartData, { kind: "trace" }>;
  assertEquals(d.kind, "trace");
  assertEquals(d.samples.length, 32);
  assertEquals(r!.unit, "ms");
  // The sweep rate is the mean beat rate, not a sampling frequency the band never had:
  // a mean interval of 799.5 ms is 1.3 beats a second.
  assertEquals(d.hz, 1.3);
});
