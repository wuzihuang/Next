import assert from 'node:assert/strict';
import test from 'node:test';
import {hostedCheckoutUrl} from './cartPricing.js';

const cart = {lines: [{variantId: 'hoop-black-knit', quantity: 2}, {variantId: 'hoop-white', quantity: 1}], discountCode: 'SAVE10'};
const variants = [
  {id: '123', title: 'Black', available: true, price: 9900},
  {id: '456', title: 'White', available: true, price: 9900},
];
test('real Shopify variant IDs preserve colors, quantities and pending discount', () => {
  assert.equal(hostedCheckoutUrl(cart, variants, 'USD', 'nextbody.myshopify.com'), 'https://nextbody.myshopify.com/cart/123:2,456:1?discount=SAVE10');
});
test('missing, unavailable, ambiguous and mismatched prices fail closed', () => {
  for (const catalog of [[], [...variants, variants[0]], variants.map(v => ({...v, available: false})), variants.map(v => ({...v, price: 10000}))]) {
    assert.throws(() => hostedCheckoutUrl(cart, catalog, 'USD', 'nextbody.myshopify.com'));
  }
});
test('checkout rejects unknown variants, wrong currency and untrusted domains', () => {
  for (const domain of ['', 'evil.com', 'nextbody.myshopify.com@evil.com', 'nextbody.myshopify.com/path']) {
    assert.throws(() => hostedCheckoutUrl(cart, variants, 'USD', domain));
  }
  assert.throws(() => hostedCheckoutUrl(cart, variants, 'CAD', 'nextbody.myshopify.com'));
  assert.throws(() => hostedCheckoutUrl({lines:[{variantId:'unknown',quantity:1}]}, variants, 'USD', 'nextbody.myshopify.com'));
  assert.throws(() => hostedCheckoutUrl({lines:[]}, variants, 'USD', 'nextbody.myshopify.com'));
});
