import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decodeArchive, encodeArchive, mergeSampleHistory } from "./archive.ts";
const row = {
  user_id: "owner",
  ts: "2024-01-01T00:00:00Z",
  src: "band",
  hr: 65,
};
Deno.test("archive roundtrip preserves samples and validates owner before exposing data", async () => {
  const archive = await encodeArchive("owner", "raw_samples", [row]);
  assertEquals(await decodeArchive(archive.bytes, archive.manifest, "owner"), [
    row,
  ]);
  await assertRejects(() =>
    decodeArchive(archive.bytes, archive.manifest, "other")
  );
});
Deno.test("archive rejects corrupt payload and tampered manifest instead of silently omitting history", async () => {
  const archive = await encodeArchive("owner", "raw_samples", [row]);
  await assertRejects(() =>
    decodeArchive(archive.bytes.slice(1), archive.manifest, "owner")
  );
  await assertRejects(() =>
    decodeArchive(archive.bytes, { ...archive.manifest, row_count: 2 }, "owner")
  );
  await assertRejects(() =>
    decodeArchive(archive.bytes, {
      ...archive.manifest,
      range_end: "2025-01-01T00:00:00Z",
    }, "owner")
  );
  await assertRejects(() =>
    decodeArchive(
      archive.bytes,
      { ...archive.manifest, format_version: 2 },
      "owner",
    )
  );
});
Deno.test("overlapping cold batches deduplicate by physical source; a corrected hot sample wins", () => {
  assertEquals(
    mergeSampleHistory([{ ...row, hr: 72 }], [row, {
      ...row,
      src: "other",
      hr: 61,
    }, row]),
    [{ ...row, hr: 72 }, { ...row, src: "other", hr: 61 }],
  );
});

import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { readSampleHistory } from "./archive.ts";
function historyDB(
  tables: Record<string, Record<string, unknown>[]>,
  payload: Uint8Array,
  failed = false,
) {
  return {
    from(table: string) {
      let rows = tables[table] ?? [];
      let lo = 0;
      let hi = 999;
      const q = {
        select() {
          return q;
        },
        eq(key: string, value: unknown) {
          rows = rows.filter((r) => r[key] === value);
          return q;
        },
        gte(key: string, value: string) {
          rows = rows.filter((r) =>
            Date.parse(String(r[key])) >= Date.parse(value)
          );
          return q;
        },
        lt(key: string, value: string) {
          rows = rows.filter((r) =>
            Date.parse(String(r[key])) < Date.parse(value)
          );
          return q;
        },
        order() {
          return q;
        },
        limit(count: number) {
          hi = count - 1;
          return q;
        },
        range(start: number, end: number) {
          lo = start;
          hi = end;
          return q;
        },
        then(resolve: (v: unknown) => unknown) {
          return Promise.resolve({
            data: rows.slice(lo, hi + 1),
            error: failed ? new Error("offline") : null,
          }).then(resolve);
        },
      };
      return q;
    },
    storage: {
      from() {
        return {
          download() {
            return Promise.resolve({
              data: new Blob([new Uint8Array(payload)]),
              error: null,
            });
          },
        };
      },
    },
  } as unknown as SupabaseClient;
}
Deno.test("public history reads cold evidence and hot corrections without overlap or other owners", async () => {
  const archive = await encodeArchive("owner", "raw_samples", [row]);
  const db = historyDB({
    sample_archives: [{
      ...archive.manifest,
      state: "verified",
      object_path: "owner/history.gz",
    }],
    raw_samples: [{ ...row, hr: 80 }, { ...row, user_id: "other" }],
  }, archive.bytes);
  assertEquals(
    await readSampleHistory(db, "owner", "2024-01-01", "2024-01-02"),
    [{ ...row, hr: 80 }],
  );
});
Deno.test("public history distinguishes no measurements from failed or corrupt retrieval", async () => {
  const archive = await encodeArchive("owner", "raw_samples", [row]);
  assertEquals(
    await readSampleHistory(
      historyDB({}, archive.bytes),
      "owner",
      "2024-01-01",
      "2024-01-02",
    ),
    [],
  );
  await assertRejects(() =>
    readSampleHistory(
      historyDB({}, archive.bytes, true),
      "owner",
      "2024-01-01",
      "2024-01-02",
    )
  );
  await assertRejects(() =>
    readSampleHistory(
      historyDB({
        sample_archives: [{
          ...archive.manifest,
          state: "verified",
          object_path: "owner/history.gz",
        }],
      }, new Uint8Array([0])),
      "owner",
      "2024-01-01",
      "2024-01-02",
    )
  );
  await assertRejects(() =>
    readSampleHistory(
      historyDB({}, archive.bytes),
      "owner",
      "not-a-date",
      "2024-01-02",
    )
  );
});
Deno.test("public history paginates all hot observations through the requested interval", async () => {
  const rows = Array.from(
    { length: 1001 },
    (_, i) => ({
      ...row,
      ts: new Date(Date.parse(row.ts) + i * 1000).toISOString(),
    }),
  );
  const result = await readSampleHistory(
    historyDB({ raw_samples: rows }, new Uint8Array()),
    "owner",
    "2024-01-01",
    "2024-01-02",
  );
  assertEquals(result.length, 1001);
  assertEquals(result[1000].ts, "2024-01-01T00:16:40.000Z");
});
Deno.test("RR archives preserve ordered input and distinguish decoder/source identity", async () => {
  const rr = {
    user_id: "owner",
    ts: row.ts,
    device_key: "band",
    mapping_version: "1",
    rr_ms: [800, 820, 810],
  };
  const encoded = await encodeArchive("owner", "band_rr_evidence", [rr]);
  assertEquals(await decodeArchive(encoded.bytes, encoded.manifest, "owner"), [
    rr,
  ]);
  assertEquals(
    mergeSampleHistory(
      [rr],
      [rr, { ...rr, mapping_version: "2" }],
      "band_rr_evidence",
    ).length,
    2,
  );
  await assertRejects(() =>
    encodeArchive("owner", "band_rr_evidence", [{ ...rr, rr_ms: ["bad"] }])
  );
});
Deno.test("tier transition during a history read retries without silently losing archived facts", async () => {
  const encoded = await encodeArchive("owner", "raw_samples", [row]);
  const tables: Record<string, Record<string, unknown>[]> = {
    sample_archives: [],
    raw_samples: [row],
  };
  const base = historyDB(tables, encoded.bytes);
  const originalFrom = base.from.bind(base);
  let moved = false;
  const moving = {
    ...base,
    from(table: string) {
      if (table === "raw_samples" && !moved) {
        moved = true;
        tables.raw_samples = [];
        tables.sample_archives = [{
          ...encoded.manifest,
          id: "new-manifest",
          state: "verified",
          object_path: "owner/history.gz",
        }];
      }
      return originalFrom(table);
    },
  } as SupabaseClient;
  assertEquals(
    await readSampleHistory(moving, "owner", "2024-01-01", "2024-01-02"),
    [row],
  );
});
