import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleMetricRead, type MetricReadDependencies } from "./index.ts";
const request = () =>
  new Request("http://localhost/metric-read", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      metrics: ["intakeKcal"],
      from: "2026-09-03",
      to: "2026-09-04",
      timezone: "UTC",
    }),
  });
function deps(
  choice: string | null = "granted",
  error: unknown = null,
): MetricReadDependencies {
  return {
    authenticate: () => Promise.resolve("u"),
    budget: () => Promise.resolve(null),
    client: () =>
      ({
        from(table: string) {
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
                data: table === "consents" ? { choice } : { timezone: "UTC" },
                error,
              });
            },
          };
          return q;
        },
      }) as never,
    read: () => Promise.resolve({ ok: true, data: [] }),
  };
}
Deno.test("metric HTTP read returns decoder-compatible envelope only after authorization", async () => {
  const response = await handleMetricRead(request(), deps());
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { ok: true, data: [] });
  const blocked = await handleMetricRead(request(), {
    ...deps(),
    authenticate: () => Promise.resolve(null),
  });
  assertEquals(blocked.status, 401);
});
Deno.test("metric HTTP read fails closed for withdrawn or unavailable consent", async () => {
  assertEquals((await handleMetricRead(request(), deps(null))).status, 403);
  assertEquals(
    (await handleMetricRead(
      request(),
      deps("granted", { message: "db unavailable" }),
    )).status,
    503,
  );
});
Deno.test("metric HTTP read rejects malformed input before reading metrics", async () => {
  const response = await handleMetricRead(
    new Request("http://localhost", {
      method: "POST",
      body: JSON.stringify({ metrics: ["madeUp"], from: "today", to: "now" }),
    }),
    deps(),
  );
  assertEquals(response.status, 422);
});

Deno.test("metric HTTP rate rejection never reads health data", async () => {
  let read = false;
  const d = deps();
  d.budget = () => Promise.resolve(new Response(null, { status: 429 }));
  d.read = () => {
    read = true;
    return Promise.resolve({ ok: true, data: [] });
  };
  assertEquals((await handleMetricRead(request(), d)).status, 429);
  assertEquals(read, false);
});
Deno.test("metric HTTP read blocks a tombstoned account before metric access", async () => {
  const dependency = deps();
  dependency.client = (() => ({
    from(table: string) {
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
            data: table === "consents" ? { choice: "granted" } : {
              timezone: "UTC",
              deletion_requested_at: "2026-09-04T00:00:00Z",
            },
            error: null,
          });
        },
      };
      return q;
    },
  })) as unknown as typeof dependency.client;
  dependency.read = () => {
    throw Error("must not read");
  };
  assertEquals((await handleMetricRead(request(), dependency)).status, 403);
});
