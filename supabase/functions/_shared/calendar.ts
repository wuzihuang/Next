const WD = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];

function tzParts(at: Date, tz: string) {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
  });
  const p = Object.fromEntries(fmt.formatToParts(at).map((x) => [x.type, x.value]));
  return {
    year: Number(p.year), month: Number(p.month), day: Number(p.day),
    hour: Number(p.hour), minute: Number(p.minute), second: Number(p.second),
  };
}

function offsetMs(at: Date, tz: string): number {
  const p = tzParts(at, tz);
  return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - at.getTime();
}

/** The instant of local hour:00; two passes settle a DST edge. */
export function zoned(dayKey: string, hour: number, tz: string): Date {
  const [y, m, d] = dayKey.split("-").map(Number);
  const wall = Date.UTC(y, m - 1, d, hour);
  let guess = wall;
  for (let i = 0; i < 2; i++) guess = wall - offsetMs(new Date(guess), tz);
  return new Date(guess);
}

/** ADR 0020: a user day runs local midnight to the following midnight. */
export function dayBounds(dayKey: string, tz: string): { start: Date; end: Date } {
  return { start: zoned(dayKey, 0, tz), end: zoned(addDays(dayKey, 1), 0, tz) };
}

export function addDays(dayKey: string, n: number): string {
  const [y, m, d] = dayKey.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

export function weekday(dayKey: string): string {
  const [y, m, d] = dayKey.split("-").map(Number);
  return WD[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
}

export function hhmm(iso: string, tz: string): string {
  const p = tzParts(new Date(iso), tz);
  return `${String(p.hour).padStart(2, "0")}:${String(p.minute).padStart(2, "0")}`;
}

export function dayOf(iso: string, tz: string): string {
  const p = tzParts(new Date(iso), tz);
  return new Date(Date.UTC(p.year, p.month - 1, p.day)).toISOString().slice(0, 10);
}
