import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { resolveTurnContext } from "./turn-context.ts";

Deno.test("a yesterday follow-up reads yesterday and keeps the prior metric", () => {
  const result = resolveTurnContext("那昨天呢？", "2026-09-04", [
    { role: "user", content: "今天压力多少？" },
    { role: "assistant", content: "The last measured stress was 35." },
  ]);
  assertEquals(result.dayKey, "2026-09-03");
  assertEquals(result.from, "2026-09-03");
  assertEquals(result.to, "2026-09-03");
  assertEquals(result.queryText, "今天压力多少？\n那昨天呢？");
});

Deno.test("a thirty-day question covers the entire inclusive range", () => {
  const result = resolveTurnContext("过去30天训练负荷怎么变化？", "2026-09-04");
  assertEquals([result.from, result.to], ["2026-08-06", "2026-09-04"]);
});

Deno.test("last week means the previous complete calendar week", () => {
  const result = resolveTurnContext("What did I eat last week?", "2026-09-04");
  assertEquals([result.from, result.to], ["2026-08-24", "2026-08-30"]);
});

Deno.test("explicit historical ranges do not include later records", () => {
  const result = resolveTurnContext(
    "体重 2026-08-01 到 2026-08-15",
    "2026-09-04",
  );
  assertEquals([result.from, result.to, result.dayKey], [
    "2026-08-01",
    "2026-08-15",
    "2026-08-15",
  ]);
});

Deno.test("invalid or reversed calendar ranges are rejected, not shifted", () => {
  assertThrows(() => resolveTurnContext("2026-02-30", "2026-09-04"));
  assertThrows(() =>
    resolveTurnContext("2026-08-15 to 2026-08-01", "2026-09-04")
  );
});

Deno.test("default windows remain source-specific, explicit days are bounded", () => {
  assertEquals(
    resolveTurnContext("HRV趋势", "2026-09-04").explicitRange,
    false,
  );
  assertEquals(
    resolveTurnContext("昨晚睡得怎样", "2026-09-04").explicitRange,
    true,
  );
  assertEquals(
    resolveTurnContext("昨晚睡得怎样", "2026-09-04").dayKey,
    "2026-09-04",
  );
});

Deno.test("a new metric follow-up keeps the previous date range", () => {
  const result = resolveTurnContext("那 HRV 呢？", "2026-09-04", [
    { role: "user", content: "上周睡眠如何？" },
    { role: "assistant", content: "Sleep analysis" },
  ]);
  assertEquals([result.from, result.to], ["2026-08-24", "2026-08-30"]);
  assertEquals(result.explicitRange, true);
});

Deno.test("multi-turn follow-ups inherit the closest date override and anchor metric", () => {
  const history = [
    { role: "user", content: "上周睡眠如何？" },
    { role: "assistant", content: "Sleep analysis" },
    { role: "user", content: "那昨天呢？" },
    { role: "assistant", content: "Yesterday analysis" },
    { role: "user", content: "还有 HRV 呢？" },
  ];
  const result = resolveTurnContext("那静息心率呢？", "2026-09-04", history);
  assertEquals([result.from, result.to], ["2026-09-03", "2026-09-03"]);
  assertEquals(
    result.queryText,
    "上周睡眠如何？\n那昨天呢？\n还有 HRV 呢？\n那静息心率呢？",
  );
  const override = resolveTurnContext(
    "那 2026-08-20 呢？",
    "2026-09-04",
    history,
  );
  assertEquals([override.from, override.to], ["2026-08-20", "2026-08-20"]);
});

Deno.test("unrelated questions and the walkback budget cannot revive old date ranges", () => {
  const history = [
    { role: "user", content: "睡眠 2026-08-01 到 2026-08-15" },
    ...Array.from(
      { length: 8 },
      () => ({ role: "user", content: "那 HRV 呢？" }),
    ),
  ];
  const bounded = resolveTurnContext("那心率呢？", "2026-09-04", history);
  assertEquals(bounded.from, "2026-09-04");
  assertEquals(bounded.queryText.includes("2026-08-01"), false);
  const unrelated = resolveTurnContext("今天的饮食", "2026-09-04", history);
  assertEquals(unrelated.queryText, "今天的饮食");
  const topicChange = resolveTurnContext("那心率呢？", "2026-09-04", [
    { role: "user", content: "上周睡眠如何？" },
    { role: "user", content: "如何开始健身？" },
  ]);
  assertEquals(topicChange.from, "2026-09-04");
  assertEquals(topicChange.queryText, "如何开始健身？\n那心率呢？");
});

Deno.test("reopening a follow-up on a later day preserves the stored absolute window", () => {
  const result = resolveTurnContext("那 HRV 呢？", "2026-09-14", [
    { role: "user", content: "上周睡眠如何？" },
  ], { from: "2026-08-24", to: "2026-08-30", queryText: "上周睡眠如何？" });
  assertEquals([result.from, result.to, result.dayKey], [
    "2026-08-24",
    "2026-08-30",
    "2026-08-30",
  ]);
  const override = resolveTurnContext("那昨天呢？", "2026-09-14", [], {
    from: "2026-08-24",
    to: "2026-08-30",
    queryText: "上周睡眠如何？",
  });
  assertEquals(override.from, "2026-09-13");
  assertEquals(override.queryText, "上周睡眠如何？\n那昨天呢？");
});

Deno.test("persisted context is bounded and cannot override a new topic", () => {
  for (
    const prior of [
      { from: "2026-02-30", to: "2026-03-01" },
      { from: "2026-09-04", to: "2026-09-03" },
      { from: "2000-01-01", to: "2026-09-04" },
      { from: "2026-09-01", to: "2026-09-04", dayKey: "2026-09-03" },
      { from: "2026-09-01", to: "2026-09-04", queryText: "x".repeat(8001) },
    ]
  ) {
    assertThrows(() =>
      resolveTurnContext("那 HRV 呢？", "2026-09-14", [], prior)
    );
  }
  const unrelated = resolveTurnContext("今天吃了什么？", "2026-09-14", [], {
    from: "2026-08-24",
    to: "2026-08-30",
    queryText: "上周睡眠如何？",
  });
  assertEquals([unrelated.from, unrelated.to], ["2026-09-14", "2026-09-14"]);
  assertEquals(unrelated.queryText, "今天吃了什么？");
});

Deno.test("routing context remains bounded across long followups", () => {
  const result = resolveTurnContext("那" + "新".repeat(7999), "2026-09-04", [{role:"user",content:"旧".repeat(8000)}]);
  assertEquals(result.queryText.length,8000);
  assertEquals(result.queryText.startsWith("那"),true);
});
