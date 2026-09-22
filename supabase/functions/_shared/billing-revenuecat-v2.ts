import { billingEnvironmentAllowed } from "./billing-environment.ts";
import { ALL_PRO_PRODUCT_IDS } from "./billing-product-ids.ts";
// REST v2 keys cannot call the v1 subscriber endpoint. These normalized fields
// are private adapter output consumed by billing.ts, never supplied by a phone.
const ORIGIN = "https://api.revenuecat.com";
type Row = Record<string, unknown>;
export type RevenueCatCustomer = {
  subscriber: Row;
  observedAt: string;
  introClaimed?: boolean;
};

export async function fetchRevenueCatV2(
  owner: string,
  project: string,
  key: string,
  fetcher: typeof fetch = fetch,
): Promise<RevenueCatCustomer | null> {
  const root = `/v2/projects/${encodeURIComponent(project)}`;
  const customer = `${root}/customers/${encodeURIComponent(owner)}`;
  // Timestamp the beginning, so a slow older read cannot overwrite a later sync.
  const observedAt = new Date().toISOString();
  const request = async (path: string): Promise<Response> => {
    const url = new URL(path, ORIGIN);
    if (url.origin !== ORIGIN || !url.pathname.startsWith(root + "/")) throw Error("RC_PAGE_SCOPE");
    return await fetcher(url, {headers: {Authorization: `Bearer ${key}`}, redirect: "error", signal: AbortSignal.timeout(15_000)});
  };
  const get = async (path: string): Promise<Row> => {
    const res = await request(path);
    if (!res.ok) throw Error("RC_UNAVAILABLE");
    const row: unknown = await res.json();
    if (!record(row)) throw Error("RC_SCHEMA");
    return row as Row;
  };
  const list = async (path: string, initial?: Row): Promise<Row[]> => {
    const expectedPath = new URL(path, ORIGIN).pathname;
    const seen = new Set<string>();
    const result: Row[] = [];
    let page: string | null = path;
    while (page) {
      const url = new URL(page, ORIGIN);
      if (url.origin !== ORIGIN || url.pathname !== expectedPath || seen.has(url.href)) throw Error("RC_PAGE_SCOPE");
      seen.add(url.href);
      const body: Row = initial ?? await get(url.href);
      initial = undefined;
      if (!Array.isArray(body.items) || !body.items.every(record)) throw Error("RC_SCHEMA");
      result.push(...body.items as Row[]);
      if (body.next_page != null && typeof body.next_page !== "string") throw Error("RC_SCHEMA");
      page = body.next_page as string | null;
    }
    return result;
  };
  // Reason codes only: no identifiers, tokens or payloads reach the log.
  const why = (reason: string, detail: Row = {}) => console.warn(`billing-sync: ${reason} ${JSON.stringify(detail)}`);
  try {
    // Resolve lookup_key to the opaque v2 entitlement ID, validating project/key
    // even when this UUID has never been seen by the SDK.
    const catalog = await list(`${root}/entitlements?limit=100`);
    const entitlement = catalog.find(row => row.lookup_key === "next_pro");
    if (!entitlement || typeof entitlement.id !== "string") { why("NO_CATALOG_ENTITLEMENT"); return null; }
    const first = await request(`${customer}/subscriptions?limit=100`);
    if (first.status === 404) {
      const exists = await request(customer);
      if (exists.status !== 404) return null;
      const error = await exists.json();
      if (error?.type !== "resource_missing") return null;
      why("CUSTOMER_UNKNOWN");
      return {subscriber: {}, observedAt, introClaimed: false};
    }
    if (!first.ok) return null;
    const firstPage: unknown = await first.json();
    if (!record(firstPage)) return null;
    const subscriptions = await list(`${customer}/subscriptions?limit=100`, firstPage as Row);
    const active = await list(`${customer}/active_entitlements?limit=100`);
    const events = await list(`${customer}/events?limit=100`);
    let introClaimed = events.some(event => {
      const body = record(event.body) ? event.body as Row : {};
      return billingEnvironmentAllowed(owner, body) &&
        ALL_PRO_PRODUCT_IDS.includes(String(body.product_id)) &&
        ["trial", "intro", "introductory"].includes(String(body.period_type).toLowerCase());
    });
    const candidates: {subscription: Row; product: string}[] = [];
    for (const subscription of subscriptions) {
      const seen = {store: subscription.store, environment: subscription.environment, status: subscription.status,
        gives_access: subscription.gives_access};
      if (!billingEnvironmentAllowed(owner, subscription)) { why("SUBSCRIPTION_ENVIRONMENT_REFUSED", seen); continue; }
      if (typeof subscription.id !== "string" || !record(subscription.entitlements)) throw Error("RC_SCHEMA");
      const associated = await list(`${root}/subscriptions/${encodeURIComponent(subscription.id)}/entitlements`, subscription.entitlements as Row);
      if (!associated.some(row => row.id === entitlement.id)) { why("SUBSCRIPTION_WITHOUT_NEXT_PRO", seen); continue; }
      introClaimed ||= subscription.status === "trialing";
      if (subscription.gives_access !== true || typeof subscription.product_id !== "string") { why("SUBSCRIPTION_NO_ACCESS", seen); continue; }
      const product = await get(`${root}/products/${encodeURIComponent(subscription.product_id)}`);
      if (typeof product.store_identifier !== "string" || !product.store_identifier) throw Error("RC_SCHEMA");
      candidates.push({subscription, product: product.store_identifier});
    }
    const access = active.find(row => row.entitlement_id === entitlement.id);
    if (!access || candidates.length === 0) {
      why("NO_ACCESS", {subscriptions: subscriptions.length, candidates: candidates.length, active_entitlement: access != null});
      return {subscriber: {}, observedAt, introClaimed};
    }
    // The account-level entitlement can aggregate sandbox and real purchases.
    // Bound every candidate by its own period, never by an unrelated Test Store
    // transaction. For store grace, v2 transactions expose its effective expiry.
    const entitlementExpiry = access.expires_at === null ? Infinity : millis(access.expires_at);
    if (entitlementExpiry === null) throw Error("RC_SCHEMA");
    const effective: {subscription: Row; product: string; expiry: number}[] = [];
    for (const candidate of candidates) {
      let end = millis(candidate.subscription.ends_at) ?? millis(candidate.subscription.current_period_ends_at);
      if (candidate.subscription.status === "in_grace_period") {
        const store = String(candidate.subscription.store).toLowerCase();
        if (["app_store", "mac_app_store", "play_store"].includes(store)) {
          const transactions = await list(`${root}/subscriptions/${encodeURIComponent(String(candidate.subscription.id))}/transactions?limit=100`);
          const expiries = transactions.filter(row => row.product_store_identifier === candidate.product)
            .map(row => millis(row.effective_expiration_date)).filter((value): value is number => value !== null);
          end = expiries.length ? Math.max(...expiries) : null;
        }
      }
      if (end === null) continue;
      effective.push({...candidate, expiry: Math.min(end, entitlementExpiry)});
    }
    effective.sort((a, b) => b.expiry - a.expiry);
    if (!effective.length) { why("NO_EXPIRY", {candidates: candidates.length}); return {subscriber: {}, observedAt, introClaimed}; }
    const {subscription, product, expiry: effectiveExpiry} = effective[0];
    const expiry = new Date(effectiveExpiry).toISOString();
    const period = subscription.status === "trialing" ? "trial" : "normal";
    const renews = ["will_renew", "will_change_product", "has_already_renewed"].includes(String(subscription.auto_renewal_status));
    return {observedAt, introClaimed, subscriber: {
      entitlements: {next_pro: {product_identifier: product, expires_date: expiry, period_type: period}},
      subscriptions: {[product]: {expires_date: expiry, period_type: period, store: subscription.store,
        unsubscribe_detected_at: renews ? null : observedAt}},
    }};
  } catch (error) {
    why("READ_FAILED", {error: error instanceof Error ? error.message : "unknown"});
    // No partial snapshot is persisted if a page or related resource is missing.
    return null;
  }
}

function record(value: unknown): boolean {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function millis(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) return null;
  return Number.isFinite(new Date(value).getTime()) ? value : null;
}
