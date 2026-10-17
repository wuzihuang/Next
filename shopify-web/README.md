# NextBody storefronts

The repository has two storefront runtimes. `shopify-theme/` is the Liquid theme
used by `nextbody.ai`; `shopify-web/` is the Hydrogen storefront and local preview.
They retain separate UI and storage: the theme uses localStorage, while Hydrogen
uses a session cookie. Both checkout flows send the cart to Shopify's hosted checkout using real variant IDs.
Shopify collects payment and delivery details and maintains the authoritative order,
payment, refund and fulfillment records. Website purchases do not share the iOS
app's health account. The old card form and local payment confirmation are retired;
old test orders are not displayed as real purchases.

## Checkout configuration and release verification

Hydrogen requires `PUBLIC_STORE_DOMAIN` to be the store's `*.myshopify.com` domain
and its existing Storefront API configuration. Set `PUBLIC_HOOP_PRODUCT_HANDLE`
to the actual HOOP product handle (default `hoop`). It reads that product with a fresh
Storefront query in the US market, validates variant IDs, availability and $99 USD
pricing, and creates a Shopify cart with `cartCreate`. It redirects only to the
returned HTTPS `checkoutUrl` on the configured store or Shopify's reported primary
domain. API failures preserve the local cart and show a retryable error. The Liquid
theme uses the Checkout product → HOOP product setting (fallback handle `hoop`),
its real variants, `shop.permanent_domain` and cart currency
and uses an official cart permalink. No Admin API token or card processing service
is added.

Publish the configured HOOP product to both the Hydrogen/Headless and Online Store channels, with exactly one variant
named Black/黑色 and one named White/白色, each available at $99 USD. The integration
rejects missing or ambiguous variants, other currencies, unavailable stock and
price drift. The fixed marketing catalog and legacy variant aliases remain
compatible, but checkout cannot silently substitute a different item or price.
If product options or price change, update the marketing catalog and this explicit
mapping together. Local shipping is an estimate; Shopify owns the final shipping,
tax, discounts and total. Discount codes are forwarded for Shopify validation;
`TEST10` no longer fabricates a 10% reduction in the local quote.

Before publishing, the merchant must verify payment-provider activation, test-mode
state, inventory, shipping rates/markets, taxes, discount rules and order email
notifications in Shopify. Validate in a duplicate/unpublished theme with Shopify's
test payment mode: both colors, multi-line cart, quantity limits, valid/invalid
codes, shipping/tax totals, abandoned checkout and retry. Confirm payment and order
in Shopify Admin, then test cancellation, refund and fulfillment notifications
there. Local browser state must never be treated as proof of payment or delivery.
Use Shopify's order status link from the confirmation email for order details.
No live theme publication, real charge, refund or shipment is performed by builds.

On 2026-10-09 a read-only request to the configured Storefront API succeeded:
the primary domain was `nextbody.ai`, but `product(handle: "hoop")` returned null and `products(first: 10)` returned
an empty list. This token currently exposes no published products.
The configured product must exist and be published to the Storefront token's channel
before Hydrogen can checkout. Live variant mapping, hosted payment, refunds
and fulfillment remain unverified. No live cart or order was created. Unit tests
cover the redirect and fail-closed behavior with controlled catalog fixtures.

Official references: [Storefront cartCreate](https://shopify.dev/docs/api/storefront/latest/mutations/cartCreate), [cart permalinks](https://shopify.dev/docs/apps/build/checkout/create-cart-permalinks)
and [Ajax Product API](https://shopify.dev/docs/api/ajax/reference/product).

Cart rules live in `app/lib/cartPricing.js`. Hydrogen imports this source directly;
Liquid loads the generated `../shopify-theme/assets/cart-pricing.js` before
`shop.js`. Product content and storefront deployment remain separate. A Hydrogen
build does not update or deploy the Liquid theme.

After changing cart rules, run these commands from `shopify-web/`:

```bash
npm run build:shop-core
npm run test:shop
```

The generator uses the existing TypeScript dependency and performs no deployment.
Commit both the source and generated asset. `npm run check:shop-core` detects
source/asset drift and runs before storefront tests and the Hydrogen build. The
same cart fixtures exercise the Hydrogen cookie adapter and the Liquid browser
script, including order totals, discounts, shipping, and legacy variant IDs.

Page copy has the same arrangement. `app/lib/policies.ts` and
`app/lib/sitePages.ts` are the source for both storefronts; the Liquid theme
carries a generated copy inside `shop.js`:

```bash
npm run build:theme-pages
```

`npm run check:theme-pages` detects drift and runs before the Hydrogen build.
The same generator creates server-rendered app privacy, terms and support snippets,
with both collection and page templates. Existing collection routes work without
creating a Shopify Page: `/collections/all?view=app-privacy`, `?view=app-terms`,
and `?view=app-support`. The optional `/pages/app-privacy`, `/pages/app-terms`,
and `/pages/app-support` routes require published Shopify Pages with corresponding
handles and template suffixes. Theme deployment is separate from generation.

The Liquid landing page is a static snapshot of the Hydrogen one. Regenerate it
with the dev server running — it rewrites the Hydrogen routes into the theme's
query-string routes and `/landing` assets into `asset_url` tags, and it also
rewrites `app/styles/landing.css` into `landing.css.liquid`:

```bash
npm run build:theme-landing
```

`npm run check:theme-landing` compares without writing. Both need `npm run dev`
in another shell, so neither runs inside the build.

## Hydrogen development

Hydrogen is Shopify’s stack for headless commerce. Hydrogen is designed to dovetail with [React Router](https://reactrouter.com/), the modern multi-strategy router for React. This template contains a **minimal setup** of components, queries and tooling to get started with Hydrogen.

[Check out Hydrogen docs](https://shopify.dev/custom-storefronts/hydrogen)
[Get familiar with React Router](https://reactrouter.com/start/framework/routing)

## What's included

- React Router
- Hydrogen
- Oxygen
- Vite
- Shopify CLI
- ESLint
- Prettier
- GraphQL generator
- TypeScript and JavaScript flavors
- Minimal setup of components and routes

## Getting started

**Requirements:**

- Node.js version 22.x or 24.x

```bash
npm create @shopify/hydrogen@latest
```

## Building for production

```bash
npm run build
```

## Local development

```bash
npm run dev
```

## Setup for using Customer Account API (`/account` section)

Follow step 1 and 2 of <https://shopify.dev/docs/custom-storefronts/building-with-the-customer-account-api/hydrogen#step-1-set-up-a-public-domain-for-local-development>
