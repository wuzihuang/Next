import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {createContext, runInContext} from 'node:vm';
import ts from 'typescript';
import * as pricing from './cartPricing.js';

const lib = new URL('./', import.meta.url);
const themeSource = readFileSync(new URL('../../../shopify-theme/assets/shop.js', lib), 'utf8');
const browserSource = readFileSync(new URL('../../../shopify-theme/assets/cart-pricing.js', lib), 'utf8');

// Execute the server's real storage/catalog adapter without a running router.
// Its relative TypeScript imports are transpiled in memory; no build output is written.
const modules = new Map<string, {exports: any}>();
function loadServerModule(url: URL): any {
  const key = url.href;
  if (modules.has(key)) return modules.get(key)!.exports;
  const module = {exports: {}};
  modules.set(key, module);
  const source = ts.transpileModule(readFileSync(url, 'utf8'), {
    fileName: fileURLToPath(url),
    compilerOptions: {allowJs: true, module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020},
  }).outputText;
  const require = (specifier: string) => {
    if (specifier === 'react-router') return {data: (value: any, options: any) => ({value, ...options}), redirect: (url: string, options: any) => ({url, ...options})};
    assert.ok(specifier.startsWith('.'), `Unexpected external dependency ${specifier}`);
    return loadServerModule(new URL(/\.[jt]s$/.test(specifier) ? specifier : `${specifier}.ts`, url));
  };
  new Function('require', 'module', 'exports', source)(require, module, module.exports);
  return module.exports;
}
const server = loadServerModule(new URL('localShop.server.ts', lib));
const serverCatalog = loadServerModule(new URL('catalog.ts', lib));

function product(handle: string, price: number) {
  return {
    handle, price, title: {en: handle, zh: handle}, options: [],
    variants: [{id: `${handle}-black`, options: {}, image: '/test.png', available: true}],
  };
}
const products = [product('hoop', 99), product('small', 19), product('fraction', 19.95)];
serverCatalog.PRODUCTS.splice(0, serverCatalog.PRODUCTS.length, ...products);

function totals(quote: any) {
  const {quantity, subtotal, discount, shipping, total} = quote;
  return {quantity, subtotal, discount, shipping, total};
}

function themeFixture(cart: pricing.CartState, checkout = false) {
  let stored = JSON.stringify({
    lines: cart.lines.map(({variantId, quantity}) => ({variantId, qty: quantity})),
    discountCode: cart.discountCode || '', orders: [], account: null,
  });
  let latestQuote: any;
  const listeners: Record<string, (event: any) => void> = {};
  const form = Object.fromEntries(Object.entries({
    card: '4242 4242 4242 4242', email: 'test@example.com', name: 'Test',
    address1: 'Test address', city: 'City', region: 'Region', zip: '12345', country: 'US',
  }).map(([name, value]) => [name, {value}]));
  form.addEventListener = (name: string, listener: (event: any) => void) => {listeners[name] = listener;};
  const root = {
    dataset: {locale: 'en'}, innerHTML: '',
    querySelector: (selector: string) => checkout && selector === '#checkout-form' ? form : null,
    querySelectorAll: () => [],
  };
  const location = new URL(`https://test.invalid/cart${checkout ? '?checkout=1' : ''}`);
  let redirect = '';
  const context = createContext({
    window: {}, URL, URLSearchParams,
    document: {getElementById: (id: string) => id === 'nb-shop' ? root : {textContent: JSON.stringify({products})}},
    localStorage: {getItem: () => stored, setItem: (_: string, value: string) => {stored = value;}},
    location: {href: location.href, pathname: location.pathname, search: location.search, assign: (value: string) => {redirect = value;}},
  });
  runInContext(browserSource, context);
  const browserPricing = context.window.NextBodyCart;
  const quoteCart = browserPricing.quoteCart;
  browserPricing.quoteCart = (...args: any[]) => {
    latestQuote = quoteCart(...args);
    return latestQuote;
  };
  runInContext(themeSource, context);
  return {
    quote: () => latestQuote,
    html: () => root.innerHTML,
    submit: () => listeners.submit({preventDefault() {}}),
    bag: () => JSON.parse(stored),
    redirect: () => redirect,
  };
}

const fixtures = [
  {name: 'discounts are pending Shopify verification and shipping estimate retains existing rules',
    cart: {lines: [{variantId: 'hoop-black', quantity: 1}], discountCode: ' test10 '},
    expected: {quantity: 1, subtotal: 99, discount: 0, shipping: 0, total: 99}},
  {name: 'smaller carts pay the flat shipping rate',
    cart: {lines: [{variantId: 'small-black', quantity: 1}]},
    expected: {quantity: 1, subtotal: 19, discount: 0, shipping: 8, total: 27}},
  {name: 'fractional prices retain cents without claiming unverified discounts',
    cart: {lines: [{variantId: 'fraction-black', quantity: 1}], discountCode: 'TEST10'},
    expected: {quantity: 1, subtotal: 19.95, discount: 0, shipping: 8, total: 27.95}},
  {name: 'unknown codes do not reduce the quote',
    cart: {lines: [{variantId: 'hoop-black', quantity: 1}], discountCode: 'NOPE'},
    expected: {quantity: 1, subtotal: 99, discount: 0, shipping: 0, total: 99}},
  {name: 'legacy and current variant ids merge before the quantity limit',
    cart: {lines: [{variantId: 'hoop-black-knit', quantity: 5}, {variantId: 'hoop-black', quantity: 5}]},
    expected: {quantity: 9, subtotal: 891, discount: 0, shipping: 0, total: 891}},
  {name: 'unknown variants and removed quantities do not appear in the quote',
    cart: {lines: [{variantId: 'deleted', quantity: 2}, {variantId: 'hoop-black', quantity: 0}]},
    expected: {quantity: 0, subtotal: 0, discount: 0, shipping: 0, total: 0}},
  {name: 'persisted fractional and oversized quantities use the same limits',
    cart: {lines: [{variantId: 'hoop-black', quantity: 1.9}, {variantId: 'small-black', quantity: 100}]},
    expected: {quantity: 10, subtotal: 270, discount: 0, shipping: 0, total: 270}},
  {name: 'empty carts never receive shipping', cart: {lines: []},
    expected: {quantity: 0, subtotal: 0, discount: 0, shipping: 0, total: 0}},
];

for (const fixture of fixtures) {
  test(fixture.name, () => {
    const session = {get: (key: string) => key === 'nb_cart' ? JSON.stringify(fixture.cart) : undefined};
    const hydrogen = server.getShopState(session, 'en');
    const theme = themeFixture(fixture.cart);
    assert.deepEqual(totals(hydrogen.totals), fixture.expected, 'Hydrogen cookie adapter');
    assert.deepEqual(totals(theme.quote()), fixture.expected, 'Liquid localStorage adapter');
    if (fixture.expected.quantity) {
      assert.ok(theme.html().includes(`<div class="is-total"><dt>Total</dt><dd>${pricing.formatMoney(fixture.expected.total)}</dd>`));
    }
  });
}

for (const runtime of ['source', 'theme asset']) {
  test(`${runtime}: cart mutations normalize old ids and never mutate the input`, () => {
    const context = createContext({window: {}});
    runInContext(browserSource, context);
    const api = runtime === 'source' ? pricing : context.window.NextBodyCart;
    const original = {lines: [{variantId: 'hoop-black-knit', quantity: 2}]};
    const added = api.addLine(original, 'hoop-black', 100);
    assert.equal(added.lines[0].quantity, 9);
    assert.equal(added.lines[0].variantId, 'hoop-black');
    assert.equal(original.lines[0].quantity, 2);
    assert.equal(api.updateLine(added, 'hoop-black-knit', 0).lines.length, 0);
    assert.equal(api.removeLine(added, 'hoop-black').lines.length, 0);
    assert.equal(api.setDiscount(added, ' test10 ').discountCode, 'TEST10');
    assert.equal(api.setDiscount(added, '').discountCode, undefined);
    assert.equal(api.formatMoney(89.1), '$89.10');
  });
}

test('checkout never accepts card details or fabricates a local payment confirmation', () => {
  const theme = themeFixture({lines: [{variantId: 'hoop-black', quantity: 1}]}, true);
  assert.ok(!theme.html().includes('name="card"'));
  assert.ok(theme.html().includes('Shopify'));
  assert.equal(theme.bag().orders.length, 0);
});

test('server checkout validates Shopify catalog and cart before a 303 redirect', async () => {
  const actions = loadServerModule(new URL('shopActions.server.ts', lib));
  const stored = {lines: [{variantId: 'hoop-black', quantity: 2}], discountCode: 'SAVE10'};
  const session = {get: (key: string) => key === 'nb_cart' ? JSON.stringify(stored) : undefined, isPending: false};
  const request = new Request('https://nextbody.ai/checkout', {method: 'POST'});
  const validCatalog = {shop: {primaryDomain: {url: 'https://nextbody.ai'}}, product: {variants: {nodes: [{id: 'gid://shopify/ProductVariant/123', title: 'Black', availableForSale: true, price: {amount: '99.00', currencyCode: 'USD'}}]}}};
  const validResult = {cartCreate: {cart: {checkoutUrl: 'https://nextbody.ai/checkouts/abc', lines: {nodes: [{quantity: 2, merchandise: {id: 'gid://shopify/ProductVariant/123'}}]}}, userErrors: [], warnings: []}};
  let input: any;
  const context = (catalog = validCatalog, result = validResult) => ({session, env: {PUBLIC_STORE_DOMAIN: 'nextbody.myshopify.com'}, storefront: {
    CacheNone: () => ({mode: 'no-store'}), query: async () => catalog,
    mutate: async (_query: any, options: any) => {input = options.variables.input; return result;},
  }});
  const success = await actions.handleCheckoutAction(request, context());
  assert.equal(success.url, 'https://nextbody.ai/checkouts/abc');
  assert.equal(success.status, 303);
  assert.equal(success.headers.get('Cache-Control'), 'no-store');
  assert.deepEqual(input.lines, [{merchandiseId: 'gid://shopify/ProductVariant/123', quantity: 2}]);
  assert.deepEqual(input.discountCodes, ['SAVE10']);
  for (const catalog of [{}, {product: null}, {product: {variants: {nodes: [null]}}}, {product: {variants: {nodes: [{title: 'Black', availableForSale: false}]}}}]) {
    assert.equal((await actions.handleCheckoutAction(request, context(catalog as any))).status, 503);
  }
  for (const result of [{}, {cartCreate: {cart: null, userErrors: []}}, {cartCreate: {cart: validResult.cartCreate.cart, userErrors: [{message: 'Unavailable'}]}}, {cartCreate: {...validResult.cartCreate, cart: {...validResult.cartCreate.cart, checkoutUrl: 'https://evil.com/checkout'}}}, {cartCreate: {...validResult.cartCreate, warnings: [{code: 'MERCHANDISE_NOT_ENOUGH_STOCK'}]}}, {cartCreate: {...validResult.cartCreate, cart: {...validResult.cartCreate.cart, lines: {nodes: []}}}}]) {
    assert.equal((await actions.handleCheckoutAction(request, context(validCatalog, result as any))).status, 503);
  }
  for (const method of ['query', 'mutate']) {
    const broken = context();
    broken.storefront[method] = async () => {throw new Error('Shopify unavailable');};
    assert.equal((await actions.handleCheckoutAction(request, broken)).status, 503);
  }
  assert.equal((await actions.handleCheckoutAction(request, {session, env: {}})).status, 503);
  assert.equal(JSON.parse(session.get('nb_cart')!).lines[0].quantity, 2);
});

test('legacy browser and server test orders are never exposed as real orders', () => {
  assert.deepEqual(server.readOrders({get: () => JSON.stringify([{id: 'old', status: 'paid_test'}])}), []);
});
