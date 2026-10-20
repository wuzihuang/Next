import assert from "node:assert/strict";
import { test } from "node:test";
import type { McpEnv } from "../functions/_lib/env.ts";
import {
  AUTHORIZATION_SERVER_PATHS,
  PROTECTED_RESOURCE_PATHS,
  handleWellKnown,
} from "../functions/_lib/metadata.ts";

const SUPABASE_URL = "https://gkgzwcxivnffsecshvfs.supabase.co";

const expected = {
  resource: "https://mcp.nextbody.ai/mcp",
  authorization_servers: [`${SUPABASE_URL}/auth/v1`],
  bearer_methods_supported: ["header"],
  scopes_supported: ["openid", "email", "profile"],
  resource_name: "NextBody",
  resource_documentation: "https://mcp.nextbody.ai/",
};

async function readMetadata(path: string, env: McpEnv, requestOrigin = "https://mcp.nextbody.ai"): Promise<Response> {
  return handleWellKnown(new Request(`${requestOrigin}${path}`), env);
}

test("protected resource metadata matches both well-known paths", async function bothPaths(): Promise<void> {
  const env: McpEnv = {
    SUPABASE_URL: `${SUPABASE_URL}/`,
    MCP_PUBLIC_ORIGIN: "https://mcp.nextbody.ai/",
  };
  assert.equal(PROTECTED_RESOURCE_PATHS.length, 2);
  for (const path of PROTECTED_RESOURCE_PATHS) {
    const response = await readMetadata(path, env);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "application/json");
    assert.equal(response.headers.get("cache-control"), "public, max-age=300");
    assert.equal(response.headers.get("access-control-allow-origin"), "*");
    assert.deepEqual(await response.json(), expected);
  }
});

test("protected resource origin falls back to the request", async function requestOrigin(): Promise<void> {
  const response = await readMetadata(
    "/.well-known/oauth-protected-resource",
    { SUPABASE_URL },
    "https://branch.pages.dev",
  );
  assert.equal(response.status, 200);
  const body = await response.json() as { resource: string; resource_documentation: string };
  assert.equal(body.resource, "https://branch.pages.dev/mcp");
  assert.equal(body.resource_documentation, "https://branch.pages.dev/");
});

test("authorization server metadata is proxied for both paths", async function authServer(): Promise<void> {
  let seen = "";
  const env: McpEnv = { SUPABASE_URL: `${SUPABASE_URL}/` };
  async function fetchImpl(input: Request | URL | string): Promise<Response> {
    seen = input instanceof URL ? input.toString() : input instanceof Request ? input.url : String(input);
    return new Response('{"issuer":"https://gkgzwcxivnffsecshvfs.supabase.co/auth/v1"}', {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }
  assert.equal(AUTHORIZATION_SERVER_PATHS.length, 2);
  for (const path of AUTHORIZATION_SERVER_PATHS) {
    const response = await handleWellKnown(new Request(`https://mcp.nextbody.ai${path}`), env, fetchImpl);
    assert.equal(response.status, 200);
    assert.equal(
      seen,
      `${SUPABASE_URL}/auth/v1/.well-known/oauth-authorization-server`,
    );
    assert.equal(response.headers.get("access-control-allow-origin"), "*");
    assert.equal(response.headers.get("content-type"), "application/json");
    assert.equal(await response.text(), '{"issuer":"https://gkgzwcxivnffsecshvfs.supabase.co/auth/v1"}');
  }
});
