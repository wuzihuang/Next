import { enforceRequestBudget } from "../_shared/rate-limit.ts";
import { ArchiveUnavailableError } from "../_shared/archive.ts";
import {
  cors,
  currentUserId,
  json,
  serviceClient,
  userClient,
} from "../_shared/db.ts";
import {
  archiveBatch,
  hydrateHistory,
  releaseHistory,
} from "../_shared/archive-worker.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const internal = Boolean(serviceKey) &&
    req.headers.get("Authorization") === `Bearer ${serviceKey}`;
  const text = await req.text();
  if (text.length > 4096) return json({ error: "PAYLOAD_TOO_LARGE" }, 413);
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return json({ error: "E_SCHEMA" }, 422);
  }
  if (
    !body ||
    (!["raw_samples", "band_rr_evidence"].includes(body.domain) &&
      body.action !== "recover" && body.action !== "release")
  ) {
    return json({ error: "E_SCHEMA" }, 422);
  }
  const userId = internal ? body.user_id : await currentUserId(req);
  if (
    typeof userId !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      userId,
    )
  ) return json({ error: "UNAUTHENTICATED" }, 401);
  const admin = serviceClient();
  const limited = await enforceRequestBudget(
    internal ? admin : userClient(req),
    "archive-data",
    internal ? userId : undefined,
  );
  if (limited) return limited;
  try {
    if (body.action === "release") {
      return json({
        state: "releasing",
        ...await releaseHistory(
          internal ? admin : userClient(req),
          admin,
          userId,
        ),
      });
    }
    if (body.action === "recover") {
      if (typeof body.from !== "string" || typeof body.to !== "string") {
        return json({ error: "E_SCHEMA" }, 422);
      }
      return json(
        await hydrateHistory(
          internal ? admin : userClient(req),
          admin,
          userId,
          body.from,
          body.to,
        ),
      );
    }
    return json(
      await archiveBatch(
        internal ? admin : userClient(req),
        admin,
        userId,
        body.domain,
      ),
    );
  } catch (error) {
    return json({
      error: "ARCHIVE_UNAVAILABLE",
      message: error instanceof ArchiveUnavailableError
        ? error.message
        : "Historical processing is temporarily unavailable; retry this request.",
    }, 503);
  }
});
