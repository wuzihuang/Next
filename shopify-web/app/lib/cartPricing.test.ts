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
  {name: '$99 HOOP with TEST10 retains cents and qualifies for free shipping',
    cart: {lines: [{variantId: 'hoop-black', quantity: 1}], discountCode: ' test10 '},
    expected: {quantity: 1, subtotal: 99, discount: 9.9, shipping: 0, total: 89.1}},
  {name: 'smaller carts pay the flat shipping rate',
    cart: {lines: [{variantId: 'small-black', quantity: 1}]},
    expected: {quantity: 1, subtotal: 19, discount: 0, shipping: 8, total: 27}},
  {name: 'fractional prices round the complete discount to a cent',
    cart: {lines: [{variantId: 'fraction-black', quantity: 1}], discountCode: 'TEST10'},
    expected: {quantity: 1, subtotal: 19.95, discount: 2, shipping: 8, total: 25.95}},
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

test('both persisted test orders use the same confirmed cart quote', () => {
  const cart = fixtures[0].cart;
  const theme = themeFixture(cart, true);
  theme.submit();
  const order = theme.bag().orders[0];
  const hydrogen = server.createOrder({account: {email: 'test@example.com', name: 'Test'}, cart, cardLast4: '4242'});
  assert.equal(order.total, 89.1);
  assert.equal(order.total, hydrogen.totals.total);
  assert.equal(order.last4, hydrogen.cardLast4);
  assert.equal(theme.bag().lines.length, 0);
  assert.match(theme.redirect(), /^\/cart\?complete=1&order=NB-/);
});
