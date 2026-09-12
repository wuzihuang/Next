// Profile › REPORT A PROBLEM. The phone sends a title, a description and up to three
// screenshots; this turns them into one GitHub issue on the product repo. The phone never
// holds the GitHub token — only the function does — and the issue body carries the build,
// the phone and the band so the report can be reproduced without a reply.

export const MAX_TITLE = 120;
export const MAX_BODY = 4000;
export const MAX_IMAGES = 3;
/// Decoded bytes per screenshot. The phone encodes at 1280 px ≤ ~600 KiB; this is the ceiling
/// the function still accepts before it answers E_SCHEMA rather than a half-uploaded issue.
export const MAX_IMAGE_BYTES = 1_500_000;
export const IMAGE_MIMES = new Set(["image/jpeg", "image/png"]);

export type FeedbackImage = { mime: string; base64: string };
/// What the phone knows about itself. Every field is optional: an old build that sends
/// fewer still files a complete issue.
export type FeedbackContext = {
  app?: string;
  build?: string;
  ios?: string;
  device?: string;
  language?: string;
  band?: string;
  timezone?: string;
};
export type FeedbackRequest = {
  title: string;
  body: string;
  images: FeedbackImage[];
  context: FeedbackContext;
};

export class FeedbackSchemaError extends Error {
  constructor(public readonly field: string) {
    super(`E_SCHEMA:${field}`);
  }
}

function str(v: unknown, field: string, max: number, required: boolean): string {
  if (v === undefined || v === null) {
    if (required) throw new FeedbackSchemaError(field);
    return "";
  }
  if (typeof v !== "string") throw new FeedbackSchemaError(field);
  const t = v.trim();
  if (required && !t) throw new FeedbackSchemaError(field);
  return t.length > max ? t.slice(0, max) : t;
}

export function parseFeedback(raw: unknown): FeedbackRequest {
  if (!raw || typeof raw !== "object") throw new FeedbackSchemaError("body");
  const r = raw as Record<string, unknown>;
  const title = str(r.title, "title", MAX_TITLE, true);
  const body = str(r.body, "body", MAX_BODY, true);
  const images: FeedbackImage[] = [];
  if (r.images !== undefined) {
    if (!Array.isArray(r.images)) throw new FeedbackSchemaError("images");
    if (r.images.length > MAX_IMAGES) throw new FeedbackSchemaError("images");
    for (const im of r.images) {
      if (!im || typeof im !== "object") throw new FeedbackSchemaError("images");
      const { mime, base64 } = im as Record<string, unknown>;
      if (typeof mime !== "string" || !IMAGE_MIMES.has(mime)) throw new FeedbackSchemaError("images.mime");
      if (typeof base64 !== "string" || !base64) throw new FeedbackSchemaError("images.data");
      // 4 base64 chars carry 3 bytes; padding makes this a slight over-estimate, which is
      // the safe side of a ceiling.
      if (Math.floor(base64.length * 3 / 4) > MAX_IMAGE_BYTES) throw new FeedbackSchemaError("images.size");
      images.push({ mime, base64 });
    }
  }
  const context: FeedbackContext = {};
  if (r.context !== undefined) {
    if (!r.context || typeof r.context !== "object") throw new FeedbackSchemaError("context");
    const c = r.context as Record<string, unknown>;
    for (const k of ["app", "build", "ios", "device", "language", "band", "timezone"] as const) {
      const v = c[k];
      if (v === undefined || v === null) continue;
      if (typeof v !== "string") throw new FeedbackSchemaError(`context.${k}`);
      context[k] = v.trim().slice(0, 80);
    }
  }
  return { title, body, images, context };
}

export function decodeBase64(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/// Markdown for the issue. The description is the reporter's own words and goes first, in
/// a quote so a pasted `#` never becomes a heading of ours; the machine facts come last so
/// the title and first line of the issue are what the person wrote.
export function issueBody(
  req: { body: string; context: FeedbackContext },
  imageUrls: string[],
  userId: string,
  sentAt: Date,
): string {
  const lines: string[] = [];
  for (const line of req.body.split(/\r?\n/)) lines.push(`> ${line}`);
  if (imageUrls.length) {
    lines.push("", "### Screenshots", "");
    imageUrls.forEach((u, i) => lines.push(`![screenshot ${i + 1}](${u})`));
  }
  const c = req.context;
  const rows: [string, string | undefined][] = [
    ["App", [c.app, c.build ? `(${c.build})` : undefined].filter(Boolean).join(" ") || undefined],
    ["iOS", c.ios],
    ["Device", c.device],
    ["Language", c.language],
    ["Band", c.band],
    ["Timezone", c.timezone],
    ["User", userId],
    ["Sent", sentAt.toISOString()],
  ];
  lines.push("", "---", "", "| | |", "|---|---|");
  for (const [k, v] of rows) if (v) lines.push(`| ${k} | ${v.replace(/\|/g, "\\|")} |`);
  lines.push("", "_Filed from the app · Profile › Report a problem_");
  return lines.join("\n");
}

export const FEEDBACK_LABELS = ["feedback", "needs-triage"];

/// One POST to the Issues API. The token is a fine-grained PAT with Issues: read & write on
/// the product repo and nothing else; `fetchImpl` is injectable so the test never leaves
/// the process.
export async function createGithubIssue(
  opts: { repo: string; token: string; title: string; body: string; labels?: string[] },
  fetchImpl: typeof fetch = fetch,
): Promise<{ number: number; url: string }> {
  const res = await fetchImpl(`https://api.github.com/repos/${opts.repo}/issues`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${opts.token}`,
      "Accept": "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json",
      "User-Agent": "nextbody-feedback",
    },
    body: JSON.stringify({
      title: opts.title,
      body: opts.body,
      labels: opts.labels ?? FEEDBACK_LABELS,
    }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`GITHUB_${res.status}: ${text.slice(0, 300)}`);
  }
  const data = await res.json();
  if (typeof data?.number !== "number" || typeof data?.html_url !== "string") {
    throw new Error("GITHUB_MALFORMED");
  }
  return { number: data.number, url: data.html_url };
}
