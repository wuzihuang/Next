// Test Store SDK keys are public. A caller can name any App User ID, so Test
// Store evidence must never grant production AI or consume a production intro
// unless the owner is explicitly allowlisted.
//
// Apple / Google sandbox is different: every transaction is signed by the store
// and only reachable from TestFlight, Xcode or App Review builds with a sandbox
// account. TestFlight testers and App Review buy in sandbox, so refusing it
// means their purchase succeeds and Pro never turns on.
const REAL_STORES = ["app_store", "mac_app_store", "play_store"];
const TEST_STORES = ["test_store", "rc_test_store"];

export function billingEnvironmentAllowed(owner: string | undefined, evidence: Record<string, unknown>): boolean {
  const environment = String(evidence.environment ?? "").toLowerCase();
  const store = String(evidence.store ?? "").toLowerCase();
  if (!["production", "sandbox"].includes(environment)) return false;
  if (REAL_STORES.includes(store)) return true;
  if (!TEST_STORES.includes(store) || !owner) return false;
  const allowlist = (Deno.env.get("REVENUECAT_TEST_ACCOUNT_ALLOWLIST") ?? "")
    .split(",").map(value => value.trim().toLowerCase()).filter(Boolean);
  return allowlist.includes(owner.toLowerCase());
}
