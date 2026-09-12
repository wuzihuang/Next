// Profile › REPORT A PROBLEM → one GitHub issue on the product repo.
//
// The phone posts { title, body, images?: [{mime, base64}], context? }. Screenshots land in
// the public `feedback-images` bucket under an unguessable path and are embedded in the issue
// by URL (the Issues API takes no attachments). The GitHub token lives only in this
// function's secrets — GITHUB_FEEDBACK_TOKEN, a fine-grained PAT with Issues: read & write on
// GITHUB_FEEDBACK_REPO (default wuzihuang/Next) and nothing else.
import { cors, currentUserId, json, serviceClient, userClient } from "../_shared/db.ts";
import { enforceRequestBudget } from "../_shared/rate-limit.ts";
import {
  createGithubIssue,
  decodeBase64,
  FeedbackSchemaError,
  issueBody,
  parseFeedback,
} from "../_shared/feedback.ts";

export const FEEDBACK_BUCKET = "feedback-images";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  const userId = await currentUserId(req);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const limited = await enforceRequestBudget(userClient(req), "feedback");
  if (limited) return limited;

  const token = Deno.env.get("GITHUB_FEEDBACK_TOKEN");
  const repo = Deno.env.get("GITHUB_FEEDBACK_REPO") ?? "wuzihuang/Next";
  if (!token) {
    console.error("feedback: GITHUB_FEEDBACK_TOKEN is not set");
    return json({ error: "FEEDBACK_UNCONFIGURED" }, 503);
  }

  let request;
  try {
    request = parseFeedback(await req.json().catch(() => null));
  } catch (e) {
    if (e instanceof FeedbackSchemaError) return json({ error: "E_SCHEMA", field: e.field }, 422);
    throw e;
  }

  const db = serviceClient();
  const sentAt = new Date();
  const stamp = sentAt.toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
  const imageUrls: string[] = [];
  for (const [i, im] of request.images.entries()) {
    const ext = im.mime === "image/png" ? "png" : "jpg";
    const path = `${userId}/${stamp}-${crypto.randomUUID()}-${i + 1}.${ext}`;
    const up = await db.storage.from(FEEDBACK_BUCKET).upload(path, decodeBase64(im.base64), {
      contentType: im.mime,
      upsert: false,
    });
    if (up.error) {
      console.error("feedback: image upload failed", up.error.message);
      return json({ error: "IMAGE_UPLOAD_FAILED" }, 502);
    }
    imageUrls.push(db.storage.from(FEEDBACK_BUCKET).getPublicUrl(path).data.publicUrl);
  }

  try {
    const issue = await createGithubIssue({
      repo,
      token,
      title: request.title,
      body: issueBody(request, imageUrls, userId, sentAt),
    });
    return json({ number: issue.number, url: issue.url });
  } catch (e) {
    console.error("feedback: github refused", e instanceof Error ? e.message : String(e));
    return json({ error: "GITHUB_UNAVAILABLE" }, 502);
  }
});
