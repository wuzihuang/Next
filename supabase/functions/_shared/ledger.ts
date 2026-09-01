// F4 §06 · the number ledger. Every number on screen has to trace back to a tool return.
//
//  1 open the ledger — recursively pull every numeric leaf out of each tool return,
//    stored as a value-sorted array rather than a map, because auditing needs a tolerance
//    and a hash table cannot answer "within 0.05". null never enters: it is not a number.
//  2 four derivations are allowed — subtract, add, round to 0 or 1 decimal, and a
//    percentage of two ledger values. Nothing else.
//  3 audit — strip the whitelisted shapes out of text slots first, then pull every
//    \d+(\.\d+)? and binary-search the ledger with a 0.05 tolerance.
//    ⚠️ Reverse those two steps and the whole screen gets rejected every day.
//  4 verdict — one miss rejects the entire frame. No partial render, no "drop that widget
//    and resend": the frame is replaced by a degraded envelope.

export class NumberLedger {
  private values: number[] = [];
  private sources = new Map<number, string>();

  add(value: unknown, path: string) {
    if (typeof value === "number" && Number.isFinite(value)) {
      this.values.push(value);
      this.sources.set(value, path);
    }
  }

  /// Recursively harvest a tool return.
  harvest(node: unknown, path = "$") {
    if (node === null || node === undefined) return;      // null is not a number
    if (typeof node === "number") return this.add(node, path);
    if (Array.isArray(node)) {
      node.forEach((v, i) => this.harvest(v, `${path}[${i}]`));
      return;
    }
    if (typeof node === "object") {
      for (const [k, v] of Object.entries(node as Record<string, unknown>)) {
        this.harvest(v, `${path}.${k}`);
      }
    }
  }

  /// Close the ledger, adding the four legal derivations of every pair.
  seal() {
    const base = [...new Set(this.values)];
    for (const v of base) {
      this.add(Math.round(v), `round(${v})`);
      this.add(Math.round(v * 10) / 10, `round1(${v})`);
    }
    for (const a of base) {
      for (const b of base) {
        if (a === b) continue;
        this.add(a - b, `${a}-${b}`);
        this.add(a + b, `${a}+${b}`);
        if (b !== 0) this.add(Math.round((a / b) * 1000) / 10, `pct(${a}/${b})`);
      }
    }
    this.values.sort((x, y) => x - y);
  }

  has(needle: number, tolerance = 0.05): boolean {
    let lo = 0, hi = this.values.length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const v = this.values[mid];
      if (Math.abs(v - needle) <= tolerance) return true;
      if (v < needle) lo = mid + 1; else hi = mid - 1;
    }
    return false;
  }
}

// Shapes that are not measurements and must be removed before the audit.
const WHITELIST = [
  /\b\d{1,2}:\d{2}\b/g,          // HH:MM
  /\b\d{4}-\d{2}-\d{2}\b/g,      // YYYY-MM-DD
  /\bZONE\s*\d\b/gi,             // ZONE n
  /\bZ[1-5]\b/g,
  /\bSLOT\s*\d\b/gi,
];

export function auditFrame(envelope: Record<string, unknown>, ledger: NumberLedger):
  { ok: true } | { ok: false; value: number } {
  const texts: string[] = [];
  const walk = (node: unknown) => {
    if (typeof node === "string") texts.push(node);
    else if (typeof node === "number") {
      // numbers inside data came straight from the tools; text is what needs auditing
    } else if (Array.isArray(node)) node.forEach(walk);
    else if (node && typeof node === "object") Object.values(node).forEach(walk);
  };
  for (const key of ["title", "sentence", "footer", "action"]) {
    const v = (envelope as Record<string, unknown>)[key];
    if (typeof v === "string") texts.push(v);
  }
  walk((envelope as Record<string, unknown>).data);

  for (const raw of texts) {
    let s = raw;
    for (const re of WHITELIST) s = s.replace(re, " ");
    for (const m of s.matchAll(/\d+(?:\.\d+)?/g)) {
      const n = Number(m[0].replace(/,/g, ""));
      if (!ledger.has(n)) return { ok: false, value: n };
    }
  }
  return { ok: true };
}
