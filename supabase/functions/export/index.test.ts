import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type ExportDependencies, handleExport } from "./index.ts";
function dependencies(failedTable?: string): ExportDependencies {
  const db = {
    from(table: string) {
      const rows = table === "meals"
        ? Array.from(
          { length: 1001 },
          (_, i) => ({ id: String(i).padStart(5, "0"), user_id: "u", kcal: i }),
        )
        : table === "profiles"
        ? [{ user_id: "u", deletion_requested_at: null }]
        : table === "conversation_messages"
        ? [{ id: "m", user_id: "u", content: "original user message" }]
        : table === "sport_heart_rate_samples"
        ? [{
          id: "receipt",
          user_id: "u",
          session_id: "session",
          continuity_id: "continuity",
          observed_at: "2026-09-01T12:00:00.125Z",
          heart_rate: 154,
        }]
        : [];
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
        range(a: number, b: number) {
          return Promise.resolve({
            data: rows.slice(a, b + 1),
            error: table === failedTable ? { message: "failure" } : null,
          });
        },
        maybeSingle() {
          return Promise.resolve({ data: rows[0] ?? null, error: null });
        },
      };
      return q;
    },
  };
  return {
    authenticate: () => Promise.resolve("u"),
    client: () => db as never,
    history: () => Promise.resolve([]),
    budget: () => Promise.resolve(null),
  };
}
Deno.test("export paginates user facts and includes canonical full conversation messages", async () => {
  const response = await handleExport(
    new Request("http://localhost/export", { method: "POST" }),
    dependencies(),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.payload["meals.ndjson"].split("\n").length, 1001);
  assertEquals(body.payload["band_origin_corrections.ndjson"], "");
  assertEquals(
    JSON.parse(body.payload["conversation_messages.ndjson"]).content,
    "original user message",
  );
  assertEquals(JSON.parse(body.payload["sport_heart_rate_samples.ndjson"]), {
    id: "receipt",
    user_id: "u",
    session_id: "session",
    continuity_id: "continuity",
    observed_at: "2026-09-01T12:00:00.125Z",
    heart_rate: 154,
  });
});
Deno.test("missing sport evidence cannot produce a complete-looking export", async () => {
  const response = await handleExport(
    new Request("http://localhost/export", { method: "POST" }),
    dependencies("sport_heart_rate_samples"),
  );
  assertEquals(response.status, 503);
  assertEquals((await response.json()).payload, undefined);
});
Deno.test("missing origin correction history cannot produce a complete-looking export", async () => {
  const response = await handleExport(
    new Request("http://localhost/export", { method: "POST" }),
    dependencies("band_origin_corrections"),
  );
  assertEquals(response.status, 503);
  assertEquals((await response.json()).payload, undefined);
});
Deno.test("export table failure returns explicit error without any partial payload", async () => {
  const response = await handleExport(
    new Request("http://localhost/export", { method: "POST" }),
    dependencies("meals"),
  );
  assertEquals(response.status, 503);
  assertEquals((await response.json()).payload, undefined);
});
Deno.test("archive failure cannot produce a seemingly complete export", async () => {
  const deps = dependencies();
  deps.history = () => Promise.reject(Error("corrupt archive"));
  const response = await handleExport(
    new Request("http://localhost/export", { method: "POST" }),
    deps,
  );
  assertEquals(response.status, 503);
  assertEquals((await response.json()).payload, undefined);
});
Deno.test("unauthenticated or rate-limited exports never return data", async () => {
  const request = new Request("http://localhost/export", { method: "POST" });
  assertEquals(
    (await handleExport(request, {
      ...dependencies(),
      authenticate: () => Promise.resolve(null),
    })).status,
    401,
  );
  assertEquals(
    (await handleExport(request, {
      ...dependencies(),
      budget: () => Promise.resolve(new Response("limited", { status: 429 })),
    })).status,
    429,
  );
});
Deno.test("per-table export budget fails explicitly instead of returning first hundred thousand rows", async () => {
  const deps = dependencies();
  const client = deps.client;
  deps.client = (req) => {
    const db = client(req);
    const from = db.from.bind(db);
    db.from = ((table: string) => {
      if (table !== "meals") return from(table);
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
        range(a: number) {
          return Promise.resolve({
            data: Array.from(
              { length: 1000 },
              (_, i) => ({ id: a + i, user_id: "u" }),
            ),
            error: null,
          });
        },
      };
      return q;
    }) as typeof db.from;
    return db;
  };
  const response = await handleExport(
    new Request("http://localhost/export", { method: "POST" }),
    deps,
  );
  assertEquals(response.status, 503);
  assertEquals((await response.json()).error, "EXPORT_BUDGET_EXCEEDED");
});
