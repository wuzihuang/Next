export const AI_DAILY_GRANT = 10;
export const AI_QUOTA_CAP = 20;

export type QuotaState = {
  remaining: number;
  settledDay: string;
};

export function daysBetween(fromDay: string, toDay: string): number {
  return (Date.parse(toDay) - Date.parse(fromDay)) / 86_400_000;
}

export function availableQuota(
  state: QuotaState | null,
  today: string,
): number {
  if (!state) return AI_DAILY_GRANT;
  const elapsed = daysBetween(state.settledDay, today);
  if (elapsed < 0) return 0;
  if (elapsed === 0) return state.remaining;
  return Math.min(AI_QUOTA_CAP, state.remaining + elapsed * AI_DAILY_GRANT);
}

export function consumeQuota(
  state: QuotaState | null,
  today: string,
): { allowed: boolean; next: QuotaState } {
  const available = availableQuota(state, today);
  if (available < 1) {
    return { allowed: false, next: { remaining: 0, settledDay: today } };
  }
  return {
    allowed: true,
    next: { remaining: available - 1, settledDay: today },
  };
}
