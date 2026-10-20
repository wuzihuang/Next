import assert from "node:assert/strict";
import { test } from "node:test";
import type { FetchLike, McpEnv } from "../functions/_lib/env.ts";
import { FORWARDED_REQUEST_HEADERS } from "../functions/_lib/http.ts";
import { handleMcp } from "../functions/_lib/mcp.ts";

const SUPABASE_URL = "https://gkgzwcxivnffsecshvfs.supabase.co";
const WWW_AUTHENTICATE =
  'Bearer realm="mcp", resource_metadata="https://mcp.nextbody.ai/.well-known/oauth-protected-resource"';

const ALLOWED = [
  "authorization",
  "content-type",
  "accept",
  "mcp-session-id",
  "mcp-protocol-version",
  "last-event-id",
];

test("proxy forwards only the allow-listed headers and keeps a 401", async function proxy401(): Promise<void> {
  assert.deepEqual([...FORWARDED_REQUEST_HEADERS], ALLOWED);
  let captured: Request | null = null;
  const fetchImpl: FetchLike = async function capture(input: Request | URL | string): Promise<Response> {
    captured = input instanceof Request ? input : new Request(input);
    return new Response('{"error":"unauthorized"}', {
      status: 401,
      statusText: "Unauthorized",
      headers: {
        "www-authenticate": WWW_AUTHENTICATE,
        "content-type": "application/json",
        "mcp-session-id": "sess-9",
        "retry-after": "5",
        "x-upstream-extra": "kept",
      },
    });
  };

  const response = await handleMcp(
    new Request("https://mcp.nextbody.ai/mcp?x=1", {
      method: "POST",
      headers: {
        authorization: "Bearer token",
        "content-type": "application/json",
        accept: "application/json, text/event-stream",
        "mcp-session-id": "sess-1",
        "mcp-protocol-version": "2025-06-18",
        "last-event-id": "9",
        cookie: "session=no",
        apikey: ["client", "must-not-win"].join("-"),
        "x-custom": "no",
        host: "mcp.nextbody.ai",
      },
      body: '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    }),
    { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY: "pk_test" },
    fetchImpl,
  );

  assert.ok(captured);
  const upstream: Request = captured;
  assert.equal(upstream.method, "POST");
  assert.equal(upstream.url, `${SUPABASE_URL}/functions/v1/mcp?x=1`);
  assert.equal(upstream.headers.get("authorization"), "Bearer token");
  assert.equal(upstream.headers.get("content-type"), "application/json");
  assert.equal(upstream.headers.get("accept"), "application/json, text/event-stream");
  assert.equal(upstream.headers.get("mcp-session-id"), "sess-1");
  assert.equal(upstream.headers.get("mcp-protocol-version"), "2025-06-18");
  assert.equal(upstream.headers.get("last-event-id"), "9");
  assert.equal(upstream.headers.get("apikey"), "pk_test");
  assert.equal(upstream.headers.get("x-forwarded-host"), "mcp.nextbody.ai");
  assert.equal(upstream.headers.get("cookie"), null);
  assert.equal(upstream.headers.get("x-custom"), null);

  const runtime = new Set(["host", "content-length"]);
  const allowed = new Set<string>([...ALLOWED, "apikey", "x-forwarded-host"]);
  for (const name of upstream.headers.keys()) {
    assert.ok(allowed.has(name) || runtime.has(name), `unexpected upstream header ${name}`);
  }

  assert.equal(response.status, 401);
  assert.equal(response.headers.get("www-authenticate"), WWW_AUTHENTICATE);
  assert.equal(response.headers.get("content-type"), "application/json");
  assert.equal(response.headers.get("mcp-session-id"), "sess-9");
  assert.equal(response.headers.get("retry-after"), "5");
  assert.equal(response.headers.get("access-control-allow-origin"), "*");
  assert.equal(
    response.headers.get("access-control-expose-headers"),
    "www-authenticate, mcp-session-id",
  );
  assert.equal(await response.text(), '{"error":"unauthorized"}');
});

test("proxy omits apikey when the publishable key is unset", async function noApiKey(): Promise<void> {
  let captured: Request | null = null;
  const fetchImpl: FetchLike = async function capture(input: Request | URL | string): Promise<Response> {
    captured = input instanceof Request ? input : new Request(input);
    return new Response(null, { status: 204 });
  };
  const env: McpEnv = { SUPABASE_URL };
  await handleMcp(new Request("https://mcp.nextbody.ai/mcp", { method: "DELETE" }), env, fetchImpl);
  assert.ok(captured);
  const upstream: Request = captured;
  assert.equal(upstream.method, "DELETE");
  assert.equal(upstream.headers.get("apikey"), null);
  assert.equal(upstream.headers.get("x-forwarded-host"), "mcp.nextbody.ai");
});

test("OPTIONS is answered locally and does not call upstream", async function options(): Promise<void> {
  let called = false;
  const fetchImpl: FetchLike = async function shouldNotRun(): Promise<Response> {
    called = true;
    return new Response("no");
  };
  const response = await handleMcp(
    new Request("https://mcp.nextbody.ai/mcp", {
      method: "OPTIONS",
      headers: { "access-control-request-headers": "authorization, content-type" },
    }),
    { SUPABASE_URL },
    fetchImpl,
  );
  assert.equal(called, false);
  assert.equal(response.status, 204);
  assert.equal(response.headers.get("access-control-allow-origin"), "*");
  assert.equal(
    response.headers.get("access-control-allow-headers"),
    "authorization, content-type, accept, mcp-session-id, mcp-protocol-version, last-event-id",
  );
  assert.equal(
    response.headers.get("access-control-expose-headers"),
    "www-authenticate, mcp-session-id",
  );
  assert.equal(response.headers.get("access-control-allow-methods"), "GET, POST, DELETE, OPTIONS");
  assert.equal(await response.text(), "");
});
