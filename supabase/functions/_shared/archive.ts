import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
export type ArchiveDomain = "raw_samples" | "band_rr_evidence";
type Row = Record<string, unknown>;
export interface ArchiveManifest {
  user_id: string;
  domain: ArchiveDomain;
  checksum: string;
  row_count: number;
  range_start: string;
  range_end: string;
  format_version: number;
}
export class ArchiveUnavailableError extends Error {
  constructor(message = "Historical archive could not be verified") {
    super(message);
    this.name = "ArchiveUnavailableError";
  }
}
const MAX_BYTES = 16 * 1024 * 1024;
export const ARCHIVE_BUCKET = "sample-history";
async function digest(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    bytes as Uint8Array<ArrayBuffer>,
  );
  return Array.from(
    new Uint8Array(hash),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
async function boundedBytes(
  stream: ReadableStream<Uint8Array>,
): Promise<Uint8Array> {
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAX_BYTES) {
        throw new ArchiveUnavailableError("Archive exceeds read budget");
      }
      chunks.push(value);
    }
  } finally {
    await reader.cancel();
  }
  const result = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}
function validateRows(
  rows: unknown,
  owner: string,
  domain: ArchiveDomain,
): asserts rows is Row[] {
  if (
    !Array.isArray(rows) || rows.length === 0 || rows.length > 5000 ||
    rows.some((r) =>
      !r || typeof r !== "object" || r.user_id !== owner ||
      typeof r.ts !== "string" || !Number.isFinite(Date.parse(r.ts))
    )
  ) {
    throw new ArchiveUnavailableError("Invalid archive rows");
  }
  if (
    rows.some((r) =>
      domain === "raw_samples"
        ? typeof r.src !== "string"
        : typeof r.device_key !== "string" ||
          typeof r.mapping_version !== "string" || !Array.isArray(r.rr_ms) ||
          r.rr_ms.some((v: unknown) =>
            typeof v !== "number" || !Number.isFinite(v)
          )
    )
  ) {
    throw new ArchiveUnavailableError("Invalid archive domain fields");
  }
}
export async function encodeArchive(
  userId: string,
  domain: ArchiveDomain,
  rows: Row[],
) {
  validateRows(rows, userId, domain);
  const raw = new TextEncoder().encode(
    JSON.stringify({ version: 1, domain, rows }),
  );
  if (raw.length > MAX_BYTES) {
    throw new ArchiveUnavailableError("Archive exceeds write budget");
  }
  const bytes = await boundedBytes(
    new Blob([raw]).stream().pipeThrough(new CompressionStream("gzip")),
  );
  const times = rows.map((r) => Date.parse(String(r.ts)));
  const manifest: ArchiveManifest = {
    user_id: userId,
    domain,
    checksum: await digest(bytes),
    row_count: rows.length,
    range_start: new Date(Math.min(...times)).toISOString(),
    range_end: new Date(Math.max(...times)).toISOString(),
    format_version: 1,
  };
  return { bytes, manifest };
}
export async function decodeArchive(
  bytes: Uint8Array,
  manifest: ArchiveManifest,
  userId: string,
): Promise<Row[]> {
  try {
    if (
      manifest.user_id !== userId || manifest.format_version !== 1 ||
      bytes.length > MAX_BYTES || await digest(bytes) !== manifest.checksum
    ) throw new ArchiveUnavailableError();
    const raw = await boundedBytes(
      new Blob([bytes as Uint8Array<ArrayBuffer>]).stream().pipeThrough(
        new DecompressionStream("gzip"),
      ),
    );
    const value = JSON.parse(new TextDecoder().decode(raw));
    validateRows(value.rows, userId, manifest.domain);
    if (
      value.version !== 1 || value.domain !== manifest.domain ||
      value.rows.length !== manifest.row_count
    ) throw new ArchiveUnavailableError();
    const times = value.rows.map((r: Row) => Date.parse(String(r.ts)));
    if (
      Math.min(...times) !== Date.parse(manifest.range_start) ||
      Math.max(...times) !== Date.parse(manifest.range_end)
    ) throw new ArchiveUnavailableError();
    return value.rows;
  } catch (error) {
    if (error instanceof ArchiveUnavailableError) throw error;
    throw new ArchiveUnavailableError();
  }
}
export function mergeSampleHistory(
  hot: Row[],
  cold: Row[],
  domain: ArchiveDomain = "raw_samples",
): Row[] {
  const identity = (r: Row) =>
    JSON.stringify(
      domain === "raw_samples"
        ? [r.user_id, Date.parse(String(r.ts)), r.src]
        : [
          r.user_id,
          r.device_key,
          Date.parse(String(r.ts)),
          r.mapping_version,
        ],
    );
  return Array.from(
    new Map([...cold, ...hot].map((r) => [identity(r), r])).values(),
  ).sort((a, b) => Date.parse(String(a.ts)) - Date.parse(String(b.ts)));
}
export async function readArchivedSamples(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
  domain: ArchiveDomain = "raw_samples",
): Promise<Row[]> {
  if (
    !Number.isFinite(Date.parse(from)) || !(Date.parse(from) < Date.parse(to))
  ) throw new ArchiveUnavailableError("Invalid history range");
  const { data, error } = await db.from("sample_archives").select("*").eq(
    "user_id",
    userId,
  ).eq("domain", domain).eq("state", "verified")
    .gte("range_end", from).lt("range_start", to).order("verified_at").limit(
      101,
    );
  if (error || (data?.length ?? 0) > 100) {
    throw new ArchiveUnavailableError(
      "Archive query failed or exceeds budget; narrow the interval",
    );
  }
  const result: Row[] = [];
  let totalBytes = 0;
  for (const manifest of data ?? []) {
    if (!manifest.object_path.startsWith(`${userId}/`)) {
      throw new ArchiveUnavailableError();
    }
    const blob = await db.storage.from(ARCHIVE_BUCKET).download(
      manifest.object_path,
    );
    if (blob.error || !blob.data) throw new ArchiveUnavailableError();
    const bytes = await boundedBytes(blob.data.stream());
    totalBytes += bytes.length;
    if (totalBytes > 32 * 1024 * 1024) {
      throw new ArchiveUnavailableError(
        "History exceeds read budget; narrow the interval",
      );
    }
    result.push(...await decodeArchive(bytes, manifest, userId));
  }
  return mergeSampleHistory(
    [],
    result.filter((r) =>
      Date.parse(String(r.ts)) >= Date.parse(from) &&
      Date.parse(String(r.ts)) < Date.parse(to)
    ),
    domain,
  );
}
async function readHistoryAttempt(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
  domain: ArchiveDomain = "raw_samples",
): Promise<Row[]> {
  const cold = await readArchivedSamples(db, userId, from, to, domain);
  const hot: Row[] = [];
  for (let offset = 0; offset < 100000; offset += 1000) {
    let query = db.from(domain).select("*").eq("user_id", userId).gte(
      "ts",
      from,
    ).lt("ts", to).order("ts");
    query = domain === "raw_samples"
      ? query.order("src")
      : query.order("device_key").order("mapping_version");
    const { data, error } = await query.range(offset, offset + 999);
    if (error) throw new ArchiveUnavailableError("Hot history query failed");
    hot.push(...data ?? []);
    if ((data?.length ?? 0) < 1000) {
      return mergeSampleHistory(hot, cold, domain);
    }
  }
  throw new ArchiveUnavailableError(
    "History exceeds read budget; narrow the interval",
  );
}

async function archiveRevision(
  db: SupabaseClient,
  owner: string,
  from: string,
  to: string,
  domain: ArchiveDomain,
) {
  const { data, error } = await db.from("sample_archives").select(
    "id,hydrated_at",
  ).eq(
    "user_id",
    owner,
  ).eq("domain", domain).eq("state", "verified")
    .gte("range_end", from).lt("range_start", to).order("id").limit(101);
  if (error || (data?.length ?? 0) > 100) {
    throw new ArchiveUnavailableError(
      "Archive revision query failed or exceeds budget",
    );
  }
  return JSON.stringify((data ?? []).map((r) => [r.id, r.hydrated_at]));
}
/** Retry a tier transition so concurrent verified pruning cannot create a read gap,
 * including offsets shifted by a batch deletion during hot pagination. */
export async function readSampleHistory(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
  domain: ArchiveDomain = "raw_samples",
): Promise<Row[]> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const before = await archiveRevision(db, userId, from, to, domain);
    const result = await readHistoryAttempt(db, userId, from, to, domain);
    const after = await archiveRevision(db, userId, from, to, domain);
    if (before === after) return result;
  }
  throw new ArchiveUnavailableError(
    "History is moving to archive; retry this interval",
  );
}
