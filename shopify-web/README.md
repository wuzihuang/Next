# NextBody storefronts

The repository has two storefront runtimes. `shopify-theme/` is the Liquid theme
used by `nextbody.ai`; `shopify-web/` is the Hydrogen storefront and local preview.
They retain separate UI and storage: the theme uses localStorage, while Hydrogen
uses a session cookie. Both checkout flows create test orders only and do not
process payments or share the iOS app's health account.

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
