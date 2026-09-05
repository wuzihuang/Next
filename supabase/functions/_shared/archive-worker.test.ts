import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { archiveBatch } from "./archive-worker.ts";
function fixture(corrupt = false, lostFinalize = false) {
  let state = "pending";
  let pruned = false;
  let removed = false;
  let uploaded = new Uint8Array();
  const table = {
    select() {
      return this;
    },
    eq() {
      return this;
    },
    lt() {
      return this;
    },
    order() {
      return this;
    },
    delete() {
      return this;
    },
    limit() {
      return Promise.resolve({
        data: [{
          user_id: "u",
          src: "band",
          ts: "2020-01-01T00:00:00Z",
          hr: 65,
        }],
        error: null,
      });
    },
    maybeSingle() {
      return Promise.resolve({ data: { state }, error: null });
    },
  };
  const bucket = {
    upload(_path: string, bytes: Uint8Array) {
      uploaded = new Uint8Array(bytes);
      return Promise.resolve({ error: null });
    },
    download() {
      return Promise.resolve({
        data: new Blob([corrupt ? new Uint8Array([0]) : uploaded]),
        error: null,
      });
    },
    remove() {
      removed = true;
      return Promise.resolve({ error: null });
    },
  };
  const db = {
    from() {
      return table;
    },
    storage: {
      from() {
        return bucket;
      },
    },
    rpc(name: string) {
      if (name === "prepare_sample_archive") {
        return Promise.resolve({
          data: "manifest",
          error: null,
        });
      }
      pruned = true;
      state = "verified";
      return Promise.resolve({
        data: 1,
        error: lostFinalize ? new Error("network") : null,
      });
    },
  } as unknown as SupabaseClient;
  return { db, outcome: () => ({ pruned, removed }) };
}
Deno.test("archive workflow prunes only after restored object passes full verification", async () => {
  const f = fixture();
  const result = await archiveBatch(f.db, f.db, "u", "raw_samples");
  assertEquals(result.state, "verified");
  assertEquals(f.outcome(), { pruned: true, removed: false });
});
Deno.test("corrupt storage readback leaves hot history intact and removes failed pending object", async () => {
  const f = fixture(true);
  await assertRejects(() => archiveBatch(f.db, f.db, "u", "raw_samples"));
  assertEquals(f.outcome(), { pruned: false, removed: true });
});
Deno.test("lost finalization response cannot delete the only verified copy", async () => {
  const f = fixture(false, true);
  await assertRejects(() => archiveBatch(f.db, f.db, "u", "raw_samples"));
  assertEquals(f.outcome(), { pruned: true, removed: false });
});

import { encodeArchive } from "./archive.ts";
import { hydrateHistory, releaseHistory } from "./archive-worker.ts";
async function recoveryFixture(count = 1, corrupt = false, stage = "needs") {
  const encoded = await encodeArchive("u", "raw_samples", [{
    user_id: "u",
    ts: "2020-01-01T00:00:00Z",
    src: "band",
    heart: 60,
  }]);
  const calls: string[] = [];
  const manifests = Array.from(
    { length: count },
    (_, id) => ({
      ...encoded.manifest,
      id: String(id),
      object_path: `u/${id}.gz`,
    }),
  );
  const q = {
    select() {
      return this;
    },
    eq() {
      return this;
    },
    is() {
      return this;
    },
    not() {
      return this;
    },
    gte() {
      return this;
    },
    lt() {
      return this;
    },
    order() {
      return this;
    },
    limit() {
      return Promise.resolve({ data: manifests, error: null });
    },
  };
  const db = {
    from() {
      return q;
    },
    storage: {
      from() {
        return {
          download() {
            return Promise.resolve({
              data: new Blob([
                corrupt ? new Uint8Array([0]) : new Uint8Array(encoded.bytes),
              ]),
              error: null,
            });
          },
        };
      },
    },
    rpc(name: string) {
      calls.push(name);
      return Promise.resolve({
        data: name === "resume_calculation"
          ? {
            pending: stage !== "complete" &&
              !(stage === "finish" &&
                calls.filter((c) => c === "resume_calculation").length > 1),
            archive_from: "2019-12-18T00:00:00Z",
            archive_to: "2020-01-08T00:00:00Z",
            next_day: "2020-01-08",
            needs_archive: stage !== "working" &&
              calls.filter((c) => c === "resume_calculation").length === 1,
          }
          : 1,
        error: null,
      });
    },
  } as unknown as SupabaseClient;
  return { db, calls };
}
Deno.test("cold recovery hydrates no more than ten batches per call before continuing", async () => {
  const f = await recoveryFixture(11);
  const result = await hydrateHistory(
    f.db,
    f.db,
    "u",
    "2020-01-01",
    "2020-01-02",
  );
  assertEquals(result.more, true);
  assertEquals(f.calls.length, 11);
  assertEquals(
    f.calls.slice(1).every((c) => c === "hydrate_sample_archive"),
    true,
  );
});
Deno.test("verified recovery resumes bounded calculation after complete hydration", async () => {
  const f = await recoveryFixture();
  const result = await hydrateHistory(
    f.db,
    f.db,
    "u",
    "2020-01-01",
    "2020-01-02",
  );
  assertEquals(result.state, "calculation_progress");
  assertEquals(f.calls, [
    "resume_calculation",
    "hydrate_sample_archive",
    "resume_calculation",
  ]);
});
Deno.test("corrupt recovery object cannot enter the hot tier or start calculation", async () => {
  const f = await recoveryFixture(1, true);
  await assertRejects(() =>
    hydrateHistory(f.db, f.db, "u", "2020-01-01", "2020-01-02")
  );
  assertEquals(f.calls, ["resume_calculation"]);
});
Deno.test("recovery cleanup uses verified existing objects and exposes bounded continuation", async () => {
  const f = await recoveryFixture(11);
  assertEquals(await releaseHistory(f.db, f.db, "u"), {
    more: true,
    next_action: "release",
  });
  assertEquals(f.calls.length, 10);
  assertEquals(f.calls.every((c) => c === "release_sample_hydration"), true);
});
Deno.test("completed recovery releases rather than rehydrating previously released objects", async () => {
  const f = await recoveryFixture(1, false, "complete");
  const result = await hydrateHistory(
    f.db,
    f.db,
    "u",
    "2020-01-01",
    "2020-01-02",
  );
  assertEquals(result.state, "releasing");
  assertEquals(f.calls, ["resume_calculation", "release_sample_hydration"]);
});
Deno.test("final recovered calculation cleans its temporary hot copy", async () => {
  const f = await recoveryFixture(1, false, "finish");
  const result = await hydrateHistory(
    f.db,
    f.db,
    "u",
    "2020-01-01",
    "2020-01-02",
  );
  assertEquals(result.state, "releasing");
  assertEquals(f.calls, [
    "resume_calculation",
    "hydrate_sample_archive",
    "resume_calculation",
    "release_sample_hydration",
  ]);
});
Deno.test("already hydrated calculation advances without downloading more evidence", async () => {
  const f = await recoveryFixture(1, false, "working");
  const result = await hydrateHistory(
    f.db,
    f.db,
    "u",
    "2020-01-01",
    "2020-01-02",
  );
  assertEquals(result.state, "calculation_progress");
  assertEquals(f.calls, ["resume_calculation"]);
  await assertRejects(() =>
    hydrateHistory(f.db, f.db, "u", "bad", "2020-01-02")
  );
});
