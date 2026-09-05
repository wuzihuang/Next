import { addDays } from "./sources.ts";

export interface ConversationEntry {
  role: string;
  content: string;
}

export interface TurnContext {
  dayKey: string;
  from: string;
  to: string;
  queryText: string;
  explicitRange: boolean;
}

export interface PreviousResolvedContext {
  from: string;
  to: string;
  dayKey?: string;
  queryText?: string;
}

/** Resolve the query window before any prefetch, using conversation only for references. */
export function resolveTurnContext(
  text: string,
  currentDay: string,
  history: ConversationEntry[] = [],
  previousResolved?: PreviousResolvedContext,
): TurnContext {
  requireDay(currentDay);
  const followup = isFollowup(text);
  // Walk only the current referential chain, never an unrelated older conversation
  // topic. Eight user turns bound the work and the routing text we carry forward.
  const chain: string[] = [];
  if (followup) {
    for (
      const entry of history.filter((entry) => entry.role === "user").slice(-8)
        .reverse()
    ) {
      chain.unshift(entry.content);
      if (!isFollowup(entry.content)) break;
    }
  }
  if (followup && previousResolved) validatePrevious(previousResolved);
  const queryText = followup && previousResolved?.queryText
    ? `${previousResolved.queryText}\n${text}`
    : [...chain, text].join("\n");
  const rangeText = hasExplicitRange(text)
    ? text
    : chain.findLast(hasExplicitRange) ?? text;
  const inheritAbsolute = followup && !hasExplicitRange(text) &&
    previousResolved;
  const [from, to] = inheritAbsolute
    ? [inheritAbsolute.from, inheritAbsolute.to]
    : requestedRange(rangeText, currentDay);
  if (from > to) throw new Error("REVERSED_DATE_RANGE");
  return {
    dayKey: to,
    from,
    to,
    queryText: queryText.slice(-8000),
    explicitRange: !!inheritAbsolute || hasExplicitRange(rangeText),
  };
}

function validatePrevious(previous: PreviousResolvedContext): void {
  requireDay(previous.from);
  requireDay(previous.to);
  const duration = (Date.parse(previous.to) - Date.parse(previous.from)) /
    864e5;
  if (
    duration < 0 || duration > 3659 ||
    (previous.dayKey !== undefined && previous.dayKey !== previous.to) ||
    (previous.queryText !== undefined &&
      (typeof previous.queryText !== "string" ||
        previous.queryText.length > 8000))
  ) {
    throw new Error("INVALID_PREVIOUS_CONTEXT");
  }
}

function isFollowup(text: string): boolean {
  return /^(那|那么|还有|what about|how about|and\b)/i.test(text.trim());
}

function hasExplicitRange(text: string): boolean {
  return /\d{4}-\d{2}-\d{2}|过去|最近|近\s*\d|上周|这周|本周|星期|昨天|昨日|前天|昨晚|今天|today|yesterday|last|past|this week/i
    .test(text);
}

export function requireDay(value: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error("INVALID_DAY");
  const date = new Date(`${value}T00:00:00Z`);
  if (
    !Number.isFinite(date.getTime()) ||
    date.toISOString().slice(0, 10) !== value
  ) {
    throw new Error("INVALID_DAY");
  }
  return value;
}

function requestedRange(text: string, day: string): [string, string] {
  const explicit = text.match(/\b\d{4}-\d{2}-\d{2}\b/g);
  if (explicit?.length) {
    if (explicit.length > 2) throw new Error("AMBIGUOUS_DATE_RANGE");
    return [requireDay(explicit[0]), requireDay(explicit.at(-1)!)];
  }
  const days = text.match(
    /(?:过去|最近|近)\s*(\d+)\s*天|(?:last|past)\s+(\d+)\s+days?/i,
  );
  if (days) {
    const count = Number(days[1] ?? days[2]);
    if (count < 1 || count > 3660) throw new Error("DATE_RANGE_TOO_LARGE");
    return [addDays(day, 1 - count), day];
  }
  if (/(上周|上星期|last week)/i.test(text)) {
    const weekday = (new Date(`${day}T00:00:00Z`).getUTCDay() + 6) % 7;
    return [addDays(day, -weekday - 7), addDays(day, -weekday - 1)];
  }
  if (/(这周|本周|本星期|this week)/i.test(text)) {
    const weekday = (new Date(`${day}T00:00:00Z`).getUTCDay() + 6) % 7;
    return [addDays(day, -weekday), day];
  }
  if (/(过去一周|最近一周|近一周|past week)/i.test(text)) {
    return [addDays(day, -6), day];
  }
  const offset = /(前天|day before yesterday)/i.test(text)
    ? -2
    : /(昨天|昨日|昨晚|yesterday|last night)/i.test(text)
    ? -1
    : 0;
  // A night's sleep is keyed by its wake day; "last night" on the current day names that row.
  const sleepNight = /(昨晚|last night)/i.test(text);
  const target = addDays(day, sleepNight ? 0 : offset);
  return [target, target];
}
