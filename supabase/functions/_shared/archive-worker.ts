import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  ARCHIVE_BUCKET,
  type ArchiveDomain,
  ArchiveUnavailableError,
  decodeArchive,
  encodeArchive,
} from "./archive.ts";
/** One bounded batch. Repeated calls advance the frontier; no hot prune precedes readback. */
export async function archiveBatch(
  db: SupabaseClient,
  admin: SupabaseClient,
  owner: string,
  domain: ArchiveDomain,
) {
  const cutoff = new Date(Date.now() - 400 * 86400000).toISOString();
  const { data: rows, error } = await db.from(domain).select("*").eq(
    "user_id",
    owner,
  ).lt("ts", cutoff).order("ts").limit(500);
  if (error) throw new ArchiveUnavailableError();
  if (!rows?.length) return { state: "complete", archived: 0 };
  const { bytes, manifest } = await encodeArchive(owner, domain, rows);
  const path = `${owner}/${crypto.randomUUID()}.json.gz`;
  const prepared = await admin.rpc("prepare_sample_archive", {
    p_owner: owner,
    p_manifest: manifest,
    p_path: path,
  });
  if (prepared.error || !prepared.data) throw new ArchiveUnavailableError();
  try {
    const uploaded = await db.storage.from(ARCHIVE_BUCKET).upload(path, bytes, {
      contentType: "application/gzip",
      upsert: false,
    });
    if (uploaded.error) throw new ArchiveUnavailableError();
    const restored = await db.storage.from(ARCHIVE_BUCKET).download(path);
    if (restored.error || !restored.data) throw new ArchiveUnavailableError();
    const verifiedRows = await decodeArchive(
      new Uint8Array(await restored.data.arrayBuffer()),
      manifest,
      owner,
    );
    const finalized = await admin.rpc("finalize_sample_archive", {
      p_owner: owner,
      p_id: prepared.data,
      p_checksum: manifest.checksum,
      p_rows: verifiedRows,
    });
    if (finalized.error) throw new ArchiveUnavailableError();
    return {
      state: "verified",
      archived: manifest.row_count,
      pruned: finalized.data,
      more: rows.length === 500,
    };
  } catch (error) {
    // A lost finalize response may already have committed: never delete a verified
    // object. On uncertainty preserve both tiers; safe deletion can be retried later.
    const check = await admin.from("sample_archives").select("state").eq(
      "user_id",
      owner,
    ).eq("id", prepared.data).maybeSingle();
    if (!check.error && check.data?.state !== "verified") {
      const removed = await admin.storage.from(ARCHIVE_BUCKET).remove([path]);
      if (!removed.error) {
        await admin.from("sample_archives").delete().eq("user_id", owner).eq(
          "id",
          prepared.data,
        ).eq("state", "pending");
      }
    }
    throw error;
  }
}

/** Restore at most ten verified batches; retries preserve corrected hot records. */
export async function hydrateHistory(
  db: SupabaseClient,
  admin: SupabaseClient,
  owner: string,
  from: string,
  to: string,
) {
  if (
    !Number.isFinite(Date.parse(from)) || !(Date.parse(from) < Date.parse(to))
  ) {
    throw new ArchiveUnavailableError("Invalid recovery interval");
  }
  const progress = await admin.rpc("resume_calculation", {
    p_owner: owner,
    p_days: 7,
  });
  if (progress.error) {
    if (progress.error.message?.includes("HISTORY_BEFORE_RETAINED_COVERAGE")) {
      throw new ArchiveUnavailableError(
        "Required historical inputs were removed before archival was introduced and cannot be reconstructed",
      );
    }
    throw new ArchiveUnavailableError("Recovery calculation unavailable");
  }
  if (progress.data?.pending === false) {
    return {
      state: "releasing",
      calculation: progress.data,
      ...await releaseHistory(db, admin, owner),
    };
  }
  if (progress.data?.needs_archive !== true) {
    return { state: "calculation_progress", calculation: progress.data };
  }
  const recoveryFrom = typeof progress.data.archive_from === "string"
    ? progress.data.archive_from
    : from;
  const recoveryTo = typeof progress.data.archive_to === "string"
    ? progress.data.archive_to
    : to;
  const { data, error } = await db.from("sample_archives").select("*").eq(
    "user_id",
    owner,
  )
    .eq("domain", "raw_samples").eq("state", "verified").is("hydrated_at", null)
    .gte("range_end", recoveryFrom).lt("range_start", recoveryTo).order(
      "range_start",
    ).limit(
      11,
    );
  if (error) throw new ArchiveUnavailableError("Recovery query failed");
  let restoredRows = 0;
  for (const manifest of (data ?? []).slice(0, 10)) {
    if (!manifest.object_path.startsWith(`${owner}/`)) {
      throw new ArchiveUnavailableError();
    }
    const restored = await db.storage.from(ARCHIVE_BUCKET).download(
      manifest.object_path,
    );
    if (restored.error || !restored.data) throw new ArchiveUnavailableError();
    if (restored.data.size > 16 * 1024 * 1024) {
      throw new ArchiveUnavailableError("Recovery batch exceeds budget");
    }
    const rows = await decodeArchive(
      new Uint8Array(await restored.data.arrayBuffer()),
      manifest,
      owner,
    );
    const hydrated = await admin.rpc("hydrate_sample_archive", {
      p_owner: owner,
      p_id: manifest.id,
      p_checksum: manifest.checksum,
      p_rows: rows,
    });
    if (hydrated.error) {
      throw new ArchiveUnavailableError("Recovery transaction failed");
    }
    restoredRows += Number(hydrated.data ?? 0);
  }
  if ((data?.length ?? 0) > 10) {
    return { state: "recovering", restored_rows: restoredRows, more: true };
  }
  const result = await admin.rpc("resume_calculation", {
    p_owner: owner,
    p_days: 7,
  });
  if (result.error) {
    throw new ArchiveUnavailableError("Recovery calculation failed");
  }
  if (result.data?.pending === false) {
    return {
      state: "releasing",
      restored_rows: restoredRows,
      calculation: result.data,
      ...await releaseHistory(db, admin, owner),
    };
  }
  return {
    state: "calculation_progress",
    restored_rows: restoredRows,
    calculation: result.data,
  };
}

export async function releaseHistory(
  db: SupabaseClient,
  admin: SupabaseClient,
  owner: string,
) {
  const { data, error } = await db.from("sample_archives").select("*").eq(
    "user_id",
    owner,
  ).eq("state", "verified").not("hydrated_at", "is", null).order("range_start")
    .limit(11);
  if (error) throw new ArchiveUnavailableError("Recovery cleanup query failed");
  for (const manifest of (data ?? []).slice(0, 10)) {
    if (!manifest.object_path.startsWith(`${owner}/`)) {
      throw new ArchiveUnavailableError();
    }
    const object = await db.storage.from(ARCHIVE_BUCKET).download(
      manifest.object_path,
    );
    if (object.error || !object.data || object.data.size > 16 * 1024 * 1024) {
      throw new ArchiveUnavailableError();
    }
    const rows = await decodeArchive(
      new Uint8Array(await object.data.arrayBuffer()),
      manifest,
      owner,
    );
    const released = await admin.rpc("release_sample_hydration", {
      p_owner: owner,
      p_id: manifest.id,
      p_checksum: manifest.checksum,
      p_rows: rows,
    });
    if (released.error) {
      throw new ArchiveUnavailableError(
        "Recovery cleanup failed; hot evidence remains recoverable",
      );
    }
  }
  return {
    more: (data?.length ?? 0) > 10,
    next_action: (data?.length ?? 0) > 10 ? "release" : null,
  };
}
