import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { handleMcp, type McpDependencies } from "./server.ts";

type Call = { name: string; args: Record<string, unknown> };
type Grant = Record<string, unknown> | { error: { code: string; message: string } };

function fakeDb(
  grant: Grant,
  tables: Record<string, unknown[]> = {},
  rpcResults: Record<string, { data?: unknown; error?: { code?: string; message?: string } }> = {},
): { db: SupabaseClient; calls: Call[]; filters: string[][] } {
  const calls: Call[] = [];
  const filters: string[][] = [];
  const db = {
    rpc(name: string, args: Record<string, unknown> = {}) {
      calls.push({ name, args });
      if (name === "touch_mcp_grant") {
        return Promise.resolve("error" in grant ? { data: null, error: grant.error } : { data: grant, error: null });
      }
      const result = rpcResults[name] ?? {};
      return Promise.resolve({ data: result.data ?? null, error: result.error ?? null });
    },
    from(table: string) {
      const applied: string[] = [table];
      filters.push(applied);
      const q: Record<string, unknown> = {};
      let start = 0;
      let end = Number.MAX_SAFE_INTEGER;
      const conditions: ((row: Record<string, unknown>) => boolean)[] = [];
      for (const op of ["select", "eq", "is", "gte", "lte", "lt", "order", "limit", "range"]) {
        q[op] = (...args: unknown[]) => {
          applied.push(`${op}:${args.map(String).join(",")}`);
          if (op === "range") [start, end] = args as number[];
          if (op === "limit") end = Number(args[0]) - 1;
          const key = String(args[0]), value = args[1];
          if (["eq", "is", "gte", "lte", "lt"].includes(op)) {
            conditions.push((row) => !(key in row) || (op === "eq" || op === "is" ? row[key] === value
              : op === "gte" ? String(row[key]) >= String(value)
              : op === "lte" ? String(row[key]) <= String(value) : String(row[key]) < String(value)));
          }
          return q;
        };
      }
      q.then = (resolve: (v: unknown) => unknown) => resolve({
        data: (tables[table] ?? []).filter((row) => conditions.every((fn) => fn(row as Record<string, unknown>))).slice(start, end + 1),
        error: null,
      });
      q.maybeSingle = () => Promise.resolve({ data: (tables[table] ?? [])[0] ?? null, error: null });
      return q;
    },
  };
  return { db: db as unknown as SupabaseClient, calls, filters };
}

const OWNER = { userId: "11111111-1111-4111-8111-111111111111", clientId: "client-1" };
const GRANT = { client_id: "client-1", client_name: "ChatGPT", can_write: true, timezone: "America/Denver", deleting: false, consent: "granted" };
const REQUEST_ID = "33333333-3333-4333-8333-333333333333";
const RECEIPT = { plate_id: "22222222-2222-4222-8222-222222222222", meal_ids: ["m1"], replay: false, day: "2026-10-18", slot: "LUNCH", total_kcal: 120 };

function deps(db: SupabaseClient, overrides: Partial<McpDependencies> = {}): McpDependencies {
  let n = 0;
  return {
    authenticate: () => Promise.resolve(OWNER),
    client: () => db,
    budget: () => Promise.resolve(null),
    publicOrigin: () => "https://mcp.nextbody.ai",
    now: () => new Date("2026-10-18T19:00:00Z"),
    newId: () => `00000000-0000-4000-8000-00000000000${n++}`,
    ...overrides,
  };
}

function post(body: unknown): Request {
  return new Request("http://localhost/mcp", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer t" },
    body: JSON.stringify(body),
  });
}

function call(name: string, args: unknown, id = 1): unknown {
  return { jsonrpc: "2.0", id, method: "tools/call", params: { name, arguments: args } };
}

async function toolPayload(res: Response): Promise<{ isError?: boolean; text: string; data: Record<string, unknown> }> {
  const body = await res.json();
  const result = body.result;
  return { isError: result.isError, text: result.content[0].text, data: result.structuredContent };
}

Deno.test("a request without a token gets 401 pointing at the protected-resource metadata", async () => {
  const { db } = fakeDb(GRANT);
  const res = await handleMcp(post({ jsonrpc: "2.0", id: 1, method: "initialize" }), deps(db, {
    authenticate: () => Promise.resolve(null),
  }));
  assertEquals(res.status, 401);
  assertEquals(
    res.headers.get("WWW-Authenticate"),
    'Bearer resource_metadata="https://mcp.nextbody.ai/.well-known/oauth-protected-resource"',
  );
});

Deno.test("OPTIONS is answered and GET has no stream", async () => {
  const { db } = fakeDb(GRANT);
  assertEquals((await handleMcp(new Request("http://localhost/mcp", { method: "OPTIONS" }), deps(db))).status, 204);
  const get = await handleMcp(new Request("http://localhost/mcp", { method: "GET" }), deps(db));
  assertEquals(get.status, 405);
  await get.body?.cancel();
});

Deno.test("initialize echoes a supported protocol and falls back to the latest otherwise", async () => {
  const { db } = fakeDb(GRANT);
  const known = await (await handleMcp(post({
    jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-03-26" },
  }), deps(db))).json();
  assertEquals(known.result.protocolVersion, "2025-03-26");
  assertEquals(known.result.serverInfo.name, "nextbody");
  const unknown = await (await handleMcp(post({
    jsonrpc: "2.0", id: 2, method: "initialize", params: { protocolVersion: "1999-01-01" },
  }), deps(db))).json();
  assertEquals(unknown.result.protocolVersion, "2025-06-18");
});

Deno.test("a notification is accepted without a body", async () => {
  const { db } = fakeDb(GRANT);
  const res = await handleMcp(post({ jsonrpc: "2.0", method: "notifications/initialized" }), deps(db));
  assertEquals(res.status, 202);
  assertEquals(await res.text(), "");
});

Deno.test("a revoked grant answers 401 invalid_token so the assistant reconnects", async () => {
  const { db } = fakeDb({ error: { code: "42501", message: "MCP_GRANT_MISSING" } });
  const res = await handleMcp(post({ jsonrpc: "2.0", id: 1, method: "tools/list" }), deps(db));
  assertEquals(res.status, 401);
  assertStringIncludes(res.headers.get("WWW-Authenticate") ?? "", 'error="invalid_token"');
  await res.body?.cancel();
});

Deno.test("withdrawn consent and account deletion close the connection", async () => {
  const withdrawn = await handleMcp(post({ jsonrpc: "2.0", id: 1, method: "tools/list" }), deps(fakeDb({ ...GRANT, consent: "withdrawn" }).db));
  assertEquals(withdrawn.status, 403);
  await withdrawn.body?.cancel();
  const deleting = await handleMcp(post({ jsonrpc: "2.0", id: 1, method: "tools/list" }), deps(fakeDb({ ...GRANT, deleting: true }).db));
  assertEquals(deleting.status, 403);
  await deleting.body?.cancel();
});

Deno.test("tools/list names every tool with a schema", async () => {
  const { db } = fakeDb(GRANT);
  const body = await (await handleMcp(post({ jsonrpc: "2.0", id: 1, method: "tools/list" }), deps(db))).json();
  const names = body.result.tools.map((t: { name: string }) => t.name);
  assertEquals(names, ["list_metrics", "read_metrics", "get_day_summary", "get_sleep_night", "list_meals", "read_health_records", "get_health_profile", "log_meal", "delete_meal"]);
  for (const tool of body.result.tools) assertEquals(tool.inputSchema.type, "object");
});

Deno.test("unknown methods and tools are JSON-RPC errors", async () => {
  const { db } = fakeDb(GRANT);
  const method = await (await handleMcp(post({ jsonrpc: "2.0", id: 1, method: "resources/list" }), deps(db))).json();
  assertEquals(method.error.code, -32601);
  const tool = await (await handleMcp(post(call("drop_tables", {})), deps(db))).json();
  assertEquals(tool.error.code, -32602);
});

Deno.test("log_meal is refused without the write grant and never reaches the database", async () => {
  const { db, calls } = fakeDb({ ...GRANT, can_write: false });
  const out = await toolPayload(await handleMcp(post(call("log_meal", {
    items: [{ name: "Beef noodle soup", kcal: 650, protein_g: 35, carb_g: 80, fat_g: 18 }],
  })), deps(db)));
  assert(out.isError);
  assertStringIncludes(out.text, "WRITE_NOT_ALLOWED");
  assertEquals(calls.map((c) => c.name), ["touch_mcp_grant"]);
});

Deno.test("log_meal writes one plate on the person's local day and recalculates it", async () => {
  const { db, calls } = fakeDb(GRANT, {}, {
    log_mcp_meal: { data: { ...RECEIPT, meal_ids: ["m1", "m2"], day: "2026-10-17", slot: "DINNER", total_kcal: 840.3 } },
    settle_now: { data: 2 },
    calculation_status: { data: [{ user_day: "2026-10-17", pending: false }] },
  });
  const out = await toolPayload(await handleMcp(post(call("log_meal", {
    request_id: REQUEST_ID,
    eaten_at: "2026-10-17T19:30:00-06:00",
    items: [
      { name: "Beef noodle soup", portion: "1 bowl", kcal: 650.26, protein_g: 35, carb_g: 80, fat_g: 18, sodium_mg: 1800 },
      { name: "Latte", portion: "12 oz", kcal: 190, protein_g: 10, carb_g: 18, fat_g: 7, fiber_g: null },
    ],
  })), deps(db)));
  assertEquals(out.isError, undefined);
  const plate = calls.find((c) => c.name === "log_mcp_meal")!;
  assertEquals(plate.args.p_request_id, REQUEST_ID);
  assertEquals(plate.args.p_eaten_at, "2026-10-18T01:30:00.000Z");
  const items = plate.args.p_items as Record<string, unknown>[];
  assertEquals(items[0].kcal, 650.3);
  assertEquals(items[0].sodium_mg, 1800);
  assertEquals("fiber_g" in items[1], false);
  assertEquals("sugar_g" in items[1], false);
  assertEquals(calls.find((c) => c.name === "settle_now")!.args, { p_days: 1 });
  assertEquals(out.data.mealIds, ["m1", "m2"]);
  assertEquals(out.data.day, "2026-10-17");
  assertEquals(out.data.dayTotalsUpdated, true);
});

Deno.test("a log_meal retry without eaten_at sends the same plate", async () => {
  const { db, calls } = fakeDb(GRANT, {}, { log_mcp_meal: { data: RECEIPT } });
  const args = {
    request_id: "33333333-3333-4333-8333-333333333333",
    items: [{ name: "Toast", kcal: 120, protein_g: 4, carb_g: 20, fat_g: 2 }],
  };
  await handleMcp(post(call("log_meal", args)), deps(db));
  await handleMcp(post(call("log_meal", args)), deps(db, { now: () => new Date("2026-10-19T19:00:07Z") }));
  const plates = calls.filter((c) => c.name === "log_mcp_meal");
  assertEquals(plates.length, 2);
  assertEquals(plates[0].args, plates[1].args);
  assertEquals("logged_at" in (plates[0].args.p_items as Record<string, unknown>[])[0], false);
});

Deno.test("log_meal reports the writer's invalid time without claiming a saved meal", async () => {
  const { db } = fakeDb(GRANT, {}, { log_mcp_meal: { error: { code: "22023", message: "INVALID_MEAL_TIME" } } });
  const old = await toolPayload(await handleMcp(post(call("log_meal", {
    request_id: REQUEST_ID,
    eaten_at: "2026-10-01T12:00:00-06:00",
    items: [{ name: "Toast", kcal: 120, protein_g: 4, carb_g: 20, fat_g: 2 }],
  })), deps(db)));
  assert(old.isError);
  const future = await toolPayload(await handleMcp(post(call("log_meal", {
    request_id: REQUEST_ID,
    eaten_at: "2026-10-19T12:00:00-06:00",
    items: [{ name: "Toast", kcal: 120, protein_g: 4, carb_g: 20, fat_g: 2 }],
  })), deps(db)));
  assert(future.isError);
  assertStringIncludes(future.text, "INVALID_MEAL_TIME");
});

Deno.test("log_meal relays the database's reason for a refusal", async () => {
  const { db } = fakeDb(GRANT, {}, {
    log_mcp_meal: { error: { code: "22023", message: "DAY_ALREADY_FASTED" } },
  });
  const out = await toolPayload(await handleMcp(post(call("log_meal", {
    request_id: REQUEST_ID,
    items: [{ name: "Toast", kcal: 120, protein_g: 4, carb_g: 20, fat_g: 2 }],
  })), deps(db)));
  assert(out.isError);
  assertStringIncludes(out.text, "DAY_ALREADY_FASTED");
});

Deno.test("list_meals hides seed rows and keeps unknown nutrients null", async () => {
  const { db, filters } = fakeDb(GRANT, {
    meals: [
      { id: "a", user_day: "2026-10-18", slot: "LUNCH", text_input: "Rice", kcal: 200, protein_g: 4, carb_g: 44, fat_g: 0.4, fiber_g: null, model_version: "app" },
      { id: "b", user_day: "2026-10-18", slot: "LUNCH", text_input: "Seed", kcal: 1, model_version: "seed" },
    ],
  });
  const out = await toolPayload(await handleMcp(post(call("list_meals", {})), deps(db)));
  const meals = out.data.meals as Record<string, unknown>[];
  assertEquals(meals.length, 1);
  assertEquals(meals[0].fiberG, null);
  assertEquals(out.data.from, "2026-10-12");
  const applied = filters.find((f) => f[0] === "meals")!;
  assert(applied.includes(`eq:user_id,${OWNER.userId}`));
  assert(applied.includes("is:deleted_at,null"));
});

Deno.test("delete_meal removes every row of a plate", async () => {
  const { db, calls } = fakeDb(GRANT, {
    meals: [{ id: "r1", user_day: "2026-10-18" }, { id: "r2", user_day: "2026-10-18" }],
  });
  const out = await toolPayload(await handleMcp(post(call("delete_meal", {
    plate_id: "22222222-2222-4222-8222-222222222222",
  })), deps(db)));
  assertEquals(out.data.deletedMealIds, ["r1", "r2"]);
  const deletes = calls.filter((c) => c.name === "apply_meal_operation");
  assertEquals(deletes.map((c) => [c.args.p_kind, c.args.p_meal_id]), [["delete", "r1"], ["delete", "r2"]]);
  assertEquals(calls.find((c) => c.name === "settle_now")!.args, { p_days: 0 });
});

Deno.test("an exhausted budget becomes a tool error with the retry time", async () => {
  const { db } = fakeDb(GRANT);
  const limited = new Response("{}", { status: 429, headers: { "Retry-After": "12" } });
  const out = await toolPayload(await handleMcp(post(call("list_metrics", {})), deps(db, {
    budget: () => Promise.resolve(limited),
  })));
  assert(out.isError);
  assertStringIncludes(out.text, "12 seconds");
});

Deno.test("read_metrics rejects metrics it cannot read", async () => {
  const { db } = fakeDb(GRANT);
  const out = await toolPayload(await handleMcp(post(call("read_metrics", {
    metrics: ["ecg"], from: "2026-10-01", to: "2026-10-02",
  })), deps(db)));
  assert(out.isError);
  assertStringIncludes(out.text, "INVALID_ARGUMENTS");
});

Deno.test("list_metrics reports the person's own today", async () => {
  const { db } = fakeDb(GRANT);
  const out = await toolPayload(await handleMcp(post(call("list_metrics", {})), deps(db)));
  assertEquals(out.data.today, "2026-10-18");
  assertEquals(out.data.timezone, "America/Denver");
});

Deno.test("a saved meal does not claim totals updated while settlement is busy", async () => {
  const { db } = fakeDb(GRANT, {}, {
    log_mcp_meal: { data: RECEIPT },
    settle_now: { data: -1 },
  });
  const out = await toolPayload(await handleMcp(post(call("log_meal", {
    request_id: "33333333-3333-4333-8333-333333333333",
    items: [{ name: "Toast", kcal: 120, protein_g: 4, carb_g: 20, fat_g: 2 }],
  })), deps(db)));
  assertEquals(out.isError, undefined);
  assertEquals(out.data.dayTotalsUpdated, false);
  assertStringIncludes(String(out.data.note), "Logged.");
  assert(!String(out.data.note).includes("has been recalculated"));
});

Deno.test("log_meal requires a request id before any write", async () => {
  const { db, calls } = fakeDb(GRANT);
  const out = await toolPayload(await handleMcp(post(call("log_meal", {
    items: [{ name: "Toast", kcal: 120, protein_g: 4, carb_g: 20, fat_g: 2 }],
  })), deps(db)));
  assert(out.isError);
  assertStringIncludes(out.text, "request_id");
  assertEquals(calls.map((c) => c.name), ["touch_mcp_grant"]);
});

Deno.test("a conflict asks for reconciliation rather than a new request id", async () => {
  const { db } = fakeDb(GRANT, {}, { log_mcp_meal: { error: { code: "23505", message: "OPERATION_CONFLICT" } } });
  const out = await toolPayload(await handleMcp(post(call("log_meal", {
    request_id: REQUEST_ID,
    items: [{ name: "Toast", kcal: 120, protein_g: 4, carb_g: 20, fat_g: 2 }],
  })), deps(db)));
  assert(out.isError);
  assertStringIncludes(out.text, "list_meals");
  assertStringIncludes(out.text, "Do not change the id");
});

Deno.test("the metric catalog includes stored daytime vitals and body composition", async () => {
  const out = await toolPayload(await handleMcp(post(call("list_metrics", {})), deps(fakeDb(GRANT).db)));
  const metrics = (out.data.metrics as { metric: string }[]).map((m) => m.metric);
  for (const metric of ["heartRate", "stress", "steps", "skinTemp", "tickHrv", "foodResponse",
    "muscleMassKg", "bodyWaterPct", "boneMassKg", "proteinPct", "bmrKcal", "inputWeightKg"]) {
    assert(metrics.includes(metric), `Missing ${metric}`);
  }
  assertEquals(out.data.canLogMeals, true);
});

Deno.test("daytime metrics return measured values and preserve unknowns", async () => {
  const { db, filters } = fakeDb(GRANT, {
    raw_samples: [{ ts: "2026-10-18T18:00:00Z", heart: 72, stress: null, step: 0, src: "band" }],
  });
  const out = await toolPayload(await handleMcp(post(call("read_metrics", {
    metrics: ["heartRate", "stress", "steps"], from: "2026-10-18", to: "2026-10-18",
  })), deps(db)));
  assertEquals(out.isError, undefined);
  const series = out.data.series as { metric: string; points: { value: unknown }[] }[];
  assertEquals(series.map((s) => [s.metric, s.points[0].value]), [["heartRate", 72], ["stress", null], ["steps", 0]]);
  assert(filters.every((f) => f.includes(`eq:user_id,${OWNER.userId}`)));
});

Deno.test("health records paginate without pretending a partial page is complete", async () => {
  const { db, filters } = fakeDb(GRANT, {
    balance_checks: [{ id: "first", rest_share: 45 }, { id: "second", rest_share: 55 }],
  });
  const out = await toolPayload(await handleMcp(post(call("read_health_records", {
    collection: "balance_checks", from: "2026-10-18", to: "2026-10-18", limit: 1,
  })), deps(db)));
  assertEquals(out.data.records, [{ id: "first", rest_share: 45 }]);
  assertEquals(out.data.nextOffset, 1);
  assert(filters.every((f) => f.includes(`eq:user_id,${OWNER.userId}`)));
});

Deno.test("health reads cannot select an arbitrary table or another user", async () => {
  const { db, filters } = fakeDb(GRANT);
  for (const args of [
    { collection: "profiles" },
    { collection: "vitals", user_id: "someone-else" },
    { collection: "vitals", from: "2026-02-30", to: "2026-03-01" },
  ]) {
    const out = await toolPayload(await handleMcp(post(call("read_health_records", args)), deps(db)));
    assert(out.isError);
  }
  assertEquals(filters.length, 0);
});

Deno.test("overnight oxygen includes the evening before the wake day and excludes daylight", async () => {
  const { db } = fakeDb({ ...GRANT, timezone: "UTC" }, {
    sleep_nights: [{ user_day: "2026-10-18", sleep_start: "2026-10-17T22:00:00.000Z", wake_at: "2026-10-18T06:00:00.000Z" }],
    oxygen_samples: [
      { ts: "2026-10-17T23:00:00.000Z", spo2: 98 },
      { ts: "2026-10-18T03:00:00.000Z", spo2: 97 },
      { ts: "2026-10-18T14:00:00.000Z", spo2: 99 },
    ],
  }, { calculation_status: { data: [] } });
  const out = await toolPayload(await handleMcp(post(call("read_metrics", {
    metrics: ["bloodOxygen"], from: "2026-10-18", to: "2026-10-18",
  })), deps(db)));
  const series = out.data.series as { points: { value: unknown }[] }[];
  assertEquals(series[0].points.map((p) => p.value), [98, 97]);
});

Deno.test("meals expose the next page instead of silently truncating food history", async () => {
  const { db } = fakeDb(GRANT, {
    meals: [{ id: "first", model_version: "app" }, { id: "second", model_version: "app" }],
  });
  const first = await toolPayload(await handleMcp(post(call("list_meals", { limit: 1 })), deps(db)));
  assertEquals((first.data.meals as { id: string }[]).map((m) => m.id), ["first"]);
  assertEquals(first.data.nextOffset, 1);
  const second = await toolPayload(await handleMcp(post(call("list_meals", { limit: 1, offset: 1 })), deps(db)));
  assertEquals((second.data.meals as { id: string }[]).map((m) => m.id), ["second"]);
  assertEquals(second.data.nextOffset, null);
});

Deno.test("temporary authentication outages return retryable 503 rather than revoking the connection", async () => {
  const { db } = fakeDb(GRANT);
  const res = await handleMcp(post(call("list_metrics", {})), deps(db, {
    authenticate: () => Promise.reject(new Error("private upstream details")),
  }));
  assertEquals(res.status, 503);
  assertEquals(res.headers.get("WWW-Authenticate"), null);
  assert(!(await res.text()).includes("private upstream details"));
});
