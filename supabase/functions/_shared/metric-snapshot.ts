import type { ReadContext as Ctx } from "./read-context.ts";
type Revision = Record<string, unknown>;
const observed = new WeakMap<Ctx, Map<string, string>>();
export async function readSnapshot(
  ctx: Ctx,
  from: string,
  to: string,
): Promise<Revision[]> {
  const { data, error } = await ctx.db.rpc("calculation_status", {
    p_from: from,
    p_to: to,
  });
  if (error) throw Error("QUERY_FAILED");
  if (!Array.isArray(data)) throw Error("QUERY_FAILED");
  return data as Revision[];
}
export function acceptSnapshot(
  ctx: Ctx,
  before: Revision[],
  after: Revision[],
) {
  const signature = (r: Revision) =>
    JSON.stringify([
      r.result_revision,
      r.input_revision,
      r.current_input_revision,
      r.calculation_as_of,
      r.pending,
    ]);
  const rows = (rs: Revision[]) =>
    rs.map((r) => [String(r.user_day), signature(r)] as [string, string]).sort((
      [a],
      [b],
    ) => a.localeCompare(b));
  if (JSON.stringify(rows(before)) !== JSON.stringify(rows(after))) {
    throw Error("SNAPSHOT_CHANGED");
  }
  const existing = observed.get(ctx) ?? new Map<string, string>();
  for (const r of after) {
    const key = String(r.user_day), value = signature(r);
    if (existing.has(key) && existing.get(key) !== value) {
      throw Error("SNAPSHOT_CHANGED");
    }
  }
  observed.set(ctx, new Map([...existing, ...rows(after)]));
}
