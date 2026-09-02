// F4 §06 · the number ledger. Every number on screen has to trace back to a tool return.
//
//  1 open the ledger — recursively pull every numeric leaf out of each tool return,
//    stored as a value-sorted array rather than a map, because auditing needs a tolerance
//    and a hash table cannot answer "within 0.05". null never enters: it is not a number.
//  2 rounding to 0 or 1 decimal is the only derivation. ⚠️ It used to add every pairwise
//    sum, difference and percentage too. F7 §08 measured what that does: with forty numbers
//    in the ledger, a randomly invented number passed the audit 60.7% of the time, and at
//    N = 288 the validator rejected nothing at all — it was still running, and it no longer
//    meant anything. 「她想说的差值，服务端必须提前替她算好」: a remainder or a delta the
//    model may want to say is returned by the tool as its own field, or is not said.
//  3 audit — strip the whitelisted shapes out of text slots first, then pull every
//    \d+(\.\d+)? and binary-search the ledger with a 0.05 tolerance.
//    ⚠️ Reverse those two steps and the whole screen gets rejected every day.
//  4 verdict — one miss rejects the entire frame. No partial render, no "drop that widget
//    and resend": the frame is replaced by a degraded envelope.

export class NumberLedger {
  private values: number[] = [];
  private sources = new Map<number, string>();

  /// ⚠️ Any add after a seal used to corrupt the audit. `has` binary-searches `values`,
  /// and only `seal` ever sorted it — so a tool that returned after the render tool sealed
  /// the ledger appended out of order and the search started missing numbers that were
  /// right there. The sort is lazy now, and the flag is what makes it correct.
  add(value: unknown, path: string) {
    if (typeof value === "number" && Number.isFinite(value)) {
      this.values.push(value);
      this.sources.set(value, path);
      this.dirty = true;
    }
  }

  /// The axes the product defines, which are not measurements.
  ///
  /// ⚠️ "52 / 100" was being rejected. 100 is not a reading — it is the top of the Body
  /// Battery scale, the same way 21 is the top of the training ring and 0 is the bottom of
  /// both. F2 fixes these, board 07's table prints them as denominators, and a frame that
  /// names its own axis is doing what the contract asks. They belong in the ledger as
  /// constants rather than in the whitelist, because a whitelist for "N %" or "N / N" would
  /// exempt real percentages too.
  seedConstants() {
    for (const [v, why] of [
      [0, "scale.min"],
      [100, "bodyBattery.max"],       // F2 §02 · BODY_BATTERY is 0–100
      [21, "trainingLoad.max"],       // F2 §03 · the ring runs to 21
      [30, "hrr.z1"], [40, "hrr.z2"], [55, "hrr.z3"], [70, "hrr.z4"], [85, "hrr.z5"],
    ] as [number, string][]) this.add(v, why);
  }

  /// Recursively harvest a tool return.
  harvest(node: unknown, path = "$") {
    if (node === null || node === undefined) return;      // null is not a number
    if (typeof node === "number") {
      this.add(node, path);
      // A signed delta is the same number said either way round: the tool returned
      // thisHalfVsPrevHalf = -3.7, the model wrote "少了 3.7", and the frame was thrown out
      // for a sign it had put into the verb.
      if (node < 0) this.add(-node, `${path}|abs`);
      return;
    }
    if (Array.isArray(node)) {
      node.forEach((v, i) => this.harvest(v, `${path}[${i}]`));
      // A series carries two facts beyond its values: how many points there are, and how
      // much time they cover. Both are things the model legitimately says out loud — "5
      // samples", "over the last 20 min", "last 7 days" — and both are properties of what
      // the tool returned, so they belong in the ledger rather than in a whitelist.
      this.add(node.length, `${path}.length`);
      this.addSpan(node, path);
      this.addAggregates(node, path);
      return;
    }
    if (typeof node === "object") {
      for (const [k, v] of Object.entries(node as Record<string, unknown>)) {
        this.harvest(v, `${path}.${k}`);
      }
    }
  }

  /// A series' total and its mean.
  ///
  /// ⚠️ Only pairwise addition is a legal derivation, so the sum of seven days was
  /// unreachable — the model answered "77.5 across 7 days · 11.1 per day average", both
  /// true of the seven values the tool had just returned, and the audit threw the frame
  /// away over the total. A total and a mean are the two things any chart caption states,
  /// and they are facts about the returned data rather than new claims about the body.
  private addAggregates(rows: unknown[], path: string) {
    // A bare array of numbers is one column; an array of rows is one column per numeric
    // key. ⚠️ Keying on `value` alone was not enough — the tools return their own column
    // names (trainingLoad, kcal_in, current_value), so the mean of a seven-day series was
    // still unreachable and a correct caption was still being rejected.
    const columns = new Map<string, number[]>();
    for (const r of rows) {
      if (typeof r === "number") {
        (columns.get("$") ?? columns.set("$", []).get("$")!).push(r);
      } else if (r && typeof r === "object") {
        for (const [k, v] of Object.entries(r as Record<string, unknown>)) {
          if (typeof v !== "number" || !Number.isFinite(v)) continue;
          (columns.get(k) ?? columns.set(k, []).get(k)!).push(v);
        }
      }
    }
    for (const [name, nums] of columns) {
      if (nums.length < 2) continue;
      const sum = nums.reduce((a, b) => a + b, 0);
      const mean = sum / nums.length;
      this.add(sum, `${path}.${name}.sum`);
      this.add(Math.round(sum * 10) / 10, `${path}.${name}.sum1`);
      this.add(Math.round(sum), `${path}.${name}.sum0`);
      this.add(mean, `${path}.${name}.mean`);
      this.add(Math.round(mean * 10) / 10, `${path}.${name}.mean1`);
      this.add(Math.round(mean), `${path}.${name}.mean0`);
      this.add(Math.min(...nums), `${path}.${name}.min`);
      this.add(Math.max(...nums), `${path}.${name}.max`);
    }
  }

  /// The span a series covers, in whichever units a person would say it in.
  private addSpan(rows: unknown[], path: string) {
    const stamps = rows
      .map((r) => (r && typeof r === "object" ? (r as Record<string, unknown>) : null))
      .map((r) => (typeof r?.ts === "string" ? r.ts : typeof r?.dayKey === "string" ? r.dayKey : null))
      .filter((v): v is string => v !== null)
      .map((v) => Date.parse(v))
      .filter((n) => Number.isFinite(n));
    if (stamps.length < 2) return;
    const ms = Math.max(...stamps) - Math.min(...stamps);
    this.add(Math.round(ms / 60_000), `${path}.minutes`);
    this.add(Math.round(ms / 3_600_000), `${path}.hours`);
    this.add(Math.round(ms / 86_400_000), `${path}.days`);
    // Inclusive day counts: eight daily points span seven days and are "the last 8 days"
    // as often as "the last 7", and both readings are honest.
    this.add(Math.round(ms / 86_400_000) + 1, `${path}.daysInclusive`);
  }

  private dirty = false;

  /// Close the ledger. Rounding is the only derivation; see the header.
  seal() {
    const base = [...new Set(this.values)];
    for (const v of base) {
      this.add(Math.round(v), `round(${v})`);
      this.add(Math.round(v * 10) / 10, `round1(${v})`);
    }
    this.dirty = true;
  }

  /// Distinct entries. F7 rule 11 caps this at 60 — see `record` in tools.ts.
  get size(): number { return new Set(this.values).size; }

  has(needle: number, tolerance = 0.05): boolean {
    if (this.dirty) {
      this.values.sort((x, y) => x - y);
      this.dirty = false;
    }
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
//
// ⚠️ Window lengths are deliberately NOT on this list. They were rejecting correct frames —
// "last 7 days: 48–65" and "down 2 from 54 over last 20 min" are both entirely true, and the
// audit threw them away over the 7 and the 20 — but whitelisting every unit-suffixed number
// would leave nothing audited, which is the whole of F4 §06. Spans are made *derivable*
// instead, in harvest(): the length of a returned series, and the minutes or days it covers,
// are facts about the data the tools returned. Traceable because they are true, not
// unchecked because they are inconvenient.
const WHITELIST = [
  // ⚠️ Timestamps first, and they must come before the date shape below. The date pattern
  // ends in \b, and in "2026-09-01T22:20:00+00:00" the character after the day is a T —
  // a word character, so the boundary fails, the whole timestamp survives the strip, and
  // the audit then rejects the frame over the year. Every series the tools return carries
  // these, so this rejected almost anything with a chart in it.
  /\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?/g,
  /\b\d{1,2}:\d{2}\b/g,          // HH:MM
  /\d{4}-\d{2}-\d{2}/g,          // YYYY-MM-DD
  /\bZONE\s*\d\b/gi,             // ZONE n
  /\bZ[1-5]\b/g,
  /\bSLOT\s*\d\b/gi,
];

export function auditFrame(envelope: Record<string, unknown>, ledger: NumberLedger):
  { ok: true } | { ok: false; value: number } {
  const texts: string[] = [];
  // ⚠️ Axis labels are not claims. 07's shapes are bins[[t, v]] and rows[{label, value}] —
  // the first element of a pair and the label-ish keys of a row name a position on an
  // axis, and "26" there is the 26th, not a reading. Auditing them rejected a correct
  // weekly chart over the day of the month. Values, sentences and footers are still
  // audited in full.
  const AXIS_KEYS = new Set(["label", "dayKey", "t", "ts", "slot", "name", "day", "date", "unit", "mode", "k"]);
  const walk = (node: unknown) => {
    if (typeof node === "string") texts.push(node);
    else if (typeof node === "number") {
      // numbers inside data came straight from the tools; text is what needs auditing
    } else if (Array.isArray(node)) {
      const isPair = node.length === 2 && typeof node[0] === "string";
      node.forEach((v, i) => { if (!(isPair && i === 0)) walk(v); });
    } else if (node && typeof node === "object") {
      for (const [k, v] of Object.entries(node as Record<string, unknown>)) {
        if (AXIS_KEYS.has(k) && typeof v === "string") continue;
        walk(v);
      }
    }
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
