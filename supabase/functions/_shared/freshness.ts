import { z } from "npm:zod@3.25.76";
export const clientFreshness = z.object({
  status: z.enum(["ready","pending","timeout","offline","failed","not_requested"]),
  pending_operations: z.number().int().min(0).max(1000000).nullable().optional(),
  calculation_pending: z.boolean().nullable().optional(),
  checked_at: z.string().datetime().optional(),
  domains: z.array(z.object({
    domain: z.string().max(24), status: z.string().max(24),
    attempted_at: z.string().nullable().optional(),
    acknowledged_end: z.string().nullable().optional(),
  }).strict()).max(5).optional(),
}).strict();
export function freshnessContext(client: z.infer<typeof clientFreshness> | undefined,
  calculation: {pending?: boolean}[], failed: boolean) {
  const pending = calculation.some(row => row.pending) || (client?.pending_operations ?? 0)>0 ||
    client?.calculation_pending || (client && !["ready","not_requested"].includes(client.status));
  return {status: failed ? "query_failed" : pending ? "partial" : "available",
    client: client ?? null, calculation,
    instruction: "Client metadata describes upload state only, never measured values. Pending, failed or timed-out inputs may be absent from cloud evidence. Explicitly explain that limitation for relevant current measurements; do not label available older evidence as complete or current."};
}
