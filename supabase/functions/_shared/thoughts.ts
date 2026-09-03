// 07 · 16 · 02 · the thought stream.
//
// The THINKING screen used to print a status label the server chose — PULLING YOUR WEEK IN —
// which is the app speaking on her behalf. What the panel shows now is her own reasoning,
// the model's `reasoning_content` deltas, as they arrive.
//
// Raw reasoning is a paragraph, and the LED holds a line. This cuts the delta stream into
// lines the board can print: one fact or one inference each, broken at a sentence end when
// there is one and at the last comma or space when the line would otherwise run past the
// panel's width. A line goes out the moment it is complete, so the phone is drawing her
// third thought while she is having her fourth.

/// One line of Doto at 12px with 0.16em tracking fits ~34 latin characters across the
/// panel's 314px stream column; a CJK glyph eats about 1.6 of those.
const MAX_W = 34;
/// Below this a line is a fragment ("嗯", "So", "Wait") — noise on a five-line display.
const MIN_W = 6;
/// A sentence ends here, and so does a line. The ASCII full stop is not in the set: it also
/// sits inside "5.2" and "series.get", so it only ends a line when whitespace follows it.
const HARD = /[。！？；!?;\n]/;
/// Where a too-long line may be broken instead.
const SOFT = /[，、,）)\]】…·:：]|\s/;

function isWide(ch: string): boolean {
  const c = ch.codePointAt(0)!;
  return (c >= 0x1100 && c <= 0x115F) || (c >= 0x2E80 && c <= 0xA4CF) ||
    (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0xF900 && c <= 0xFAFF) ||
    (c >= 0xFE30 && c <= 0xFE6F) || (c >= 0xFF00 && c <= 0xFF60) ||
    (c >= 0xFFE0 && c <= 0xFFE6);
}

export function width(s: string): number {
  let w = 0;
  for (const ch of s) w += isWide(ch) ? 1.6 : 1;
  return w;
}

/// Reasoning arrives as prose with the model's own markup habits in it. None of that
/// survives onto an LED: no asterisks, no backticks, no headings, no leading bullet.
function clean(s: string): string {
  return s
    .replace(/[*_`#>]+/g, "")
    .replace(/^\s*[-–—•·]+\s*/, "")
    .replace(/\s+/g, " ")
    .replace(/^[\s，、,.。;；:：)）\]】"'"']+/, "")
    // The full stop it was cut on is not printed; a question mark is — it says she is asking
    // herself something rather than concluding.
    .replace(/[\s，、,.。;；]+$/, "")
    .trim();
}

/// Cuts the model's reasoning into printable lines and hands each one to `emit` as soon as
/// it is whole. `push` may be called with any fragment — a single character or a paragraph.
export class ThoughtStream {
  private buf = "";
  private last = "";
  private count = 0;

  constructor(
    private emit: (text: string) => void,
    /// F5 C7 · the frame's words are scanned for banned phrases before they reach the
    /// screen, and reasoning reaches the same screen. A thought that says something the
    /// product is not allowed to say is dropped, not printed and apologised for.
    private banned: RegExp[] = [],
    /// A runaway reasoning block must not become a thousand-event stream.
    private max = 48,
  ) {}

  push(delta: string) {
    this.buf += delta;
    for (;;) {
      const cut = this.cut(this.buf);
      if (cut < 0) return;
      const line = this.buf.slice(0, cut);
      this.buf = this.buf.slice(cut);
      this.offer(line);
    }
  }

  /// The tail of the reasoning is a thought too — it just never got its full stop.
  flush() {
    const rest = this.buf;
    this.buf = "";
    if (rest.trim()) this.offer(rest, true);
  }

  /// Returns how many characters of `s` form a complete line, or -1 for "need more input".
  private cut(s: string): number {
    const chars = Array.from(s);
    let w = 0, soft = -1;
    let i = 0;
    for (let k = 0; k < chars.length; k++) {
      const ch = chars[k], next = chars[k + 1];
      const n = ch.length; // surrogate pairs count as one glyph, two indices
      if (HARD.test(ch)) return i + n;
      // "read the week. Then" ends a line; "5.2" and "series.get" do not. A full stop at the
      // very end of the buffer waits for the next delta to say which of the two it is.
      if (ch === "." && next !== undefined && /\s/.test(next)) return i + n;
      w += isWide(ch) ? 1.6 : 1;
      i += n;
      if (SOFT.test(ch) && w >= MIN_W) soft = i;
      if (w > MAX_W) return soft > 0 ? soft : i;
    }
    return -1;
  }

  private offer(raw: string, tail = false) {
    if (this.count >= this.max) return;
    const line = clean(raw);
    if (!line) return;
    // A tail is allowed to be short — it is the last thing she said before rendering.
    if (width(line) < (tail ? 3 : MIN_W)) return;
    if (line === this.last) return;
    if (this.banned.some((re) => re.test(line))) return;
    this.last = line;
    this.count += 1;
    this.emit(line);
  }
}
