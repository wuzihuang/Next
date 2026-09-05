import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type Ctx, fetchAs, SOURCE_BY_ID } from "./sources.ts";
import { readSeriesSource } from "./tools.ts";
Deno.test("series evidence retains paired history and reuses chart snapshot", async () => {
  let calls = 0;
  const src = {
    id: "test.pair",
    kind: "pair" as const,
    says: "test",
    fetch: () => {
      calls++;
      return Promise.resolve({
        data: {
          kind: "pair" as const,
          hi: [["a", 99] as [string, number]],
          lo: [["a", 1] as [string, number]],
        },
        agg: { max: 99 },
        window: "DAY",
      });
    },
  };
  SOURCE_BY_ID.set(src.id, src);
  try {
    const ctx = {
      db:{rpc:()=>Promise.resolve({data:[],error:null})},
      dayKey: "2026-09-04",
      tz: "UTC",
      userId: "u",
      cache: new Map(),
    } as unknown as Ctx;
    const read = await readSeriesSource(src.id, ctx);
    assertEquals(read?.paired, { hi: [["a", 99]], lo: [["a", 1]] });
    await fetchAs(src.id, "pair", ctx);
    assertEquals(calls, 1);
  } finally {
    SOURCE_BY_ID.delete(src.id);
  }
});
function sleepContext(rows: Record<string, unknown>[]): Ctx {
  const db = {
    rpc:()=>Promise.resolve({data:[],error:null}),
    from() {
      let data = rows;
      const q = {
        select() {
          return q;
        },
        eq(k: string, v: unknown) {
          if (k !== "user_id") data = data.filter((r) => r[k] === v);
          return q;
        },
        lte(k: string, v: string) {
          data = data.filter((r) => String(r[k]) <= v);
          return q;
        },
        order() {
          return q;
        },
        limit() {
          return q;
        },
        maybeSingle() {
          return Promise.resolve({ data: data.at(-1) ?? null, error: null });
        },
      };
      return q;
    },
  };
  return {
    db: db as unknown as Ctx["db"],
    userId: "u",
    dayKey: "2026-09-04",
    tz: "UTC",
  };
}
Deno.test("missing requested night never relabels an older sleep as last night", async () => {
  assertEquals(
    await fetchAs(
      "sleep.mix",
      "stack",
      sleepContext([{
        user_day: "2026-09-03",
        total_minutes: 400,
        deep_minutes: 100,
        light_minutes: 300,
      }]),
    ),
    null,
  );
});
Deno.test("sleep strip uses actual SDK stage runs and preserves REM", async () => {
  const r = await fetchAs(
    "sleep.stages",
    "strip",
    sleepContext([{
      user_day: "2026-09-04",
      sleep_line: "1:20,0:10,2:5,4:2",
      sleep_start: "2026-09-04T00:00:00Z",
      wake_at: "2026-09-04T00:37:00Z",
    }]),
  );
  assertEquals(r?.data, {
    kind: "strip",
    lanes: [[1, 20], [2, 10], [3, 5], [0, 2]],
    from: "00:00",
    to: "00:37",
  });
  assertEquals(r?.agg.rem, 5);
});
Deno.test("source query failure stays distinguishable from absent measurements", async () => {
  const ctx = sleepContext([]);
  ctx.db = {
    from() {
      const q = {
        select() {
          return q;
        },
        eq() {
          return q;
        },
        order() {
          return q;
        },
        limit() {
          return q;
        },
        maybeSingle() {
          return Promise.resolve({
            data: null,
            error: { message: "unavailable" },
          });
        },
      };
      return q;
    },
  } as unknown as Ctx["db"];
  let failed = false;
  try {
    await fetchAs("sleep.mix", "stack", ctx);
  } catch {
    failed = true;
  }
  assertEquals(failed, true);
});
