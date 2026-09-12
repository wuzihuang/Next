import { assertEquals, assertThrows, assertStringIncludes, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  createGithubIssue,
  FeedbackSchemaError,
  issueBody,
  MAX_BODY,
  parseFeedback,
} from "./feedback.ts";

Deno.test("a title and a description are the whole minimum", () => {
  const r = parseFeedback({ title: "  Sleep page blank  ", body: "Opened it this morning, nothing." });
  assertEquals(r.title, "Sleep page blank");
  assertEquals(r.images, []);
  assertEquals(r.context, {});
});

Deno.test("an empty title or body is E_SCHEMA, not an empty issue", () => {
  assertThrows(() => parseFeedback({ title: "   ", body: "x" }), FeedbackSchemaError);
  assertThrows(() => parseFeedback({ title: "x" }), FeedbackSchemaError);
  assertThrows(() => parseFeedback(null), FeedbackSchemaError);
});

Deno.test("long text is clipped, never rejected", () => {
  const r = parseFeedback({ title: "t", body: "a".repeat(MAX_BODY + 500) });
  assertEquals(r.body.length, MAX_BODY);
});

Deno.test("images are capped at three and at the byte ceiling, jpeg or png only", () => {
  const one = { mime: "image/jpeg", base64: btoa("abc") };
  assertEquals(parseFeedback({ title: "t", body: "b", images: [one, one, one] }).images.length, 3);
  assertThrows(() => parseFeedback({ title: "t", body: "b", images: [one, one, one, one] }), FeedbackSchemaError);
  assertThrows(() => parseFeedback({ title: "t", body: "b", images: [{ mime: "image/gif", base64: "AAAA" }] }), FeedbackSchemaError);
  const huge = { mime: "image/png", base64: "A".repeat(2_100_000) };
  assertThrows(() => parseFeedback({ title: "t", body: "b", images: [huge] }), FeedbackSchemaError);
});

Deno.test("context fields are strings, trimmed, and optional one by one", () => {
  const r = parseFeedback({ title: "t", body: "b", context: { app: " 1.4.2 ", ios: "26.3", band: null } });
  assertEquals(r.context, { app: "1.4.2", ios: "26.3" });
  assertThrows(() => parseFeedback({ title: "t", body: "b", context: { app: 5 } }), FeedbackSchemaError);
});

Deno.test("the issue body quotes the reporter, embeds screenshots, and ends with the facts table", () => {
  const md = issueBody(
    { body: "# not a heading\nsecond line", context: { app: "1.4.2", build: "2831", ios: "26.3", device: "iPhone17,2", band: "HOOP · fw 2.1 · connected" } },
    ["https://x/a.jpg", "https://x/b.jpg"],
    "user-1",
    new Date("2026-09-12T10:00:00Z"),
  );
  assertStringIncludes(md, "> # not a heading\n> second line");
  assertStringIncludes(md, "![screenshot 1](https://x/a.jpg)");
  assertStringIncludes(md, "![screenshot 2](https://x/b.jpg)");
  assertStringIncludes(md, "| App | 1.4.2 (2831) |");
  assertStringIncludes(md, "| Band | HOOP · fw 2.1 · connected |");
  assertStringIncludes(md, "| User | user-1 |");
  assertStringIncludes(md, "| Sent | 2026-09-12T10:00:00.000Z |");
  // The quote comes before the table: the person's words lead.
  assertEquals(md.indexOf("> #") < md.indexOf("| App"), true);
});

Deno.test("a missing context leaves its rows out instead of printing undefined", () => {
  const md = issueBody({ body: "b", context: {} }, [], "u", new Date(0));
  assertEquals(md.includes("undefined"), false);
  assertEquals(md.includes("| App |"), false);
  assertEquals(md.includes("### Screenshots"), false);
});

Deno.test("createGithubIssue posts to the repo's issues with the bearer token and returns number + url", async () => {
  let seen: { url: string; init: RequestInit } | undefined;
  const fetchImpl = ((url: string, init: RequestInit) => {
    seen = { url, init };
    return Promise.resolve(new Response(JSON.stringify({ number: 42, html_url: "https://github.com/o/r/issues/42" }), { status: 201 }));
  }) as unknown as typeof fetch;
  const out = await createGithubIssue({ repo: "o/r", token: "tok", title: "T", body: "B" }, fetchImpl);
  assertEquals(out, { number: 42, url: "https://github.com/o/r/issues/42" });
  assertEquals(seen?.url, "https://api.github.com/repos/o/r/issues");
  const headers = seen?.init.headers as Record<string, string>;
  assertEquals(headers.Authorization, "Bearer tok");
  const sent = JSON.parse(seen?.init.body as string);
  assertEquals(sent.labels, ["feedback", "needs-triage"]);
});

Deno.test("a GitHub error surfaces its status rather than a fake issue number", async () => {
  const fetchImpl = (() => Promise.resolve(new Response("bad creds", { status: 401 }))) as unknown as typeof fetch;
  await assertRejects(() => createGithubIssue({ repo: "o/r", token: "t", title: "T", body: "B" }, fetchImpl), Error, "GITHUB_401");
});
