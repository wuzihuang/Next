import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  createTurnContext,
  withTurnRange,
  workflowRangeSchema,
} from "./turn-context.ts";

Deno.test("question wording never chooses or inherits a date range", () => {
  for (
    const text of [
      "那昨天呢？",
      "过去30天训练负荷怎么变化？",
      "What did I eat last week?",
      "体重 2026-08-01 到 2026-08-15",
      "那 HRV 呢？",
      "2026-02-30",
      "2026-09-05 to 2026-09-01",
      "昨晚睡得怎样",
    ]
  ) {
    assertEquals(createTurnContext("2026-09-05", text), {
      dayKey: "2026-09-05",
      from: "2026-09-05",
      to: "2026-09-05",
      queryText: text,
      explicitRange: false,
    });
  }
});

Deno.test("only model-selected range updates dates and preserves the original question", () => {
  const original = createTurnContext("2026-09-05", "那昨天呢？");
  const selected = withTurnRange(original, {
    from: "2026-08-24",
    to: "2026-08-30",
  });
  assertEquals(selected, {
    dayKey: "2026-08-30",
    from: "2026-08-24",
    to: "2026-08-30",
    queryText: "那昨天呢？",
    explicitRange: true,
  });
  assertEquals(original.dayKey, "2026-09-05");
  assertEquals(original.explicitRange, false);
});

Deno.test("range schema accepts actual dates including leap days and single days", () => {
  for (
    const range of [
      { from: "2024-02-29", to: "2024-02-29" },
      { from: "2024-01-01", to: "2024-12-31" },
      { from: "2025-01-01", to: "2026-01-01" },
    ]
  ) assertEquals(workflowRangeSchema.parse(range), range);
});

Deno.test("range schema rejects malformed, impossible, reversed and oversized ranges", () => {
  for (
    const range of [
      { from: "2026-02-29", to: "2026-03-01" },
      { from: "2026-02-30", to: "2026-03-01" },
      { from: "2026-09-05", to: "2026-09-04" },
      { from: "2024-01-01", to: "2025-01-01" },
      { from: "2026-9-05", to: "2026-09-05" },
      { from: "2026-09-05T00:00:00Z", to: "2026-09-05" },
      { from: "yesterday", to: "today" },
      { from: "2026-09-05", to: "2026-13-01" },
      { from: "", to: "2026-09-05" },
    ]
  ) {
    assertEquals(workflowRangeSchema.safeParse(range).success, false);
    assertThrows(() =>
      withTurnRange(createTurnContext("2026-09-05", "test"), range)
    );
  }
});

Deno.test("invalid default calendar day fails before building context", () => {
  for (const day of ["2026-02-30", "2026-9-05", "today"]) {
    assertThrows(() => createTurnContext(day, "test"));
  }
});

Deno.test("stored question remains bounded without expanding history", () => {
  const context = createTurnContext("2026-09-05", "old" + "新".repeat(8000));
  assertEquals(context.queryText, "新".repeat(8000));
});
