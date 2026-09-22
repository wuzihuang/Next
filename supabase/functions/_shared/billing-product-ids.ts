// The store products that grant `next_pro`. Yearly is what sells since 2026-09-20;
// monthly stays so the subscribers who hold one keep renewing into Pro. Its own module
// because both billing.ts and the RevenueCat adapter need it and import each other.
export const PRO_PRODUCT_IDS = ["hoop_pro_yearly", "hoop_pro_monthly"] as const;
export const TEST_STORE_PRO_PRODUCT_IDS = ["yearly", "monthly"] as const;
export const ALL_PRO_PRODUCT_IDS: readonly string[] = [...PRO_PRODUCT_IDS, ...TEST_STORE_PRO_PRODUCT_IDS];
