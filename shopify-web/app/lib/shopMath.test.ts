import assert from 'node:assert/strict';
import test from 'node:test';
import {
  addLine,
  cardLast4,
  cartSubtotal,
  cartTotal,
  discountAmount,
  emptyCart,
  formatMoney,
  isExpiryValid,
  isTestCardNumber,
  makeOrderId,
  removeLine,
  setDiscount,
  shippingAmount,
  updateLine,
} from './shopMath.ts';

test('addLine merges the same variant and clamps quantity', () => {
  const cart = addLine(addLine(emptyCart(), 'hoop-black-knit', 2), 'hoop-black-knit', 2);
  assert.equal(cart.lines[0]?.quantity, 4);
  const clamped = addLine(cart, 'hoop-black-knit', 9);
  assert.equal(clamped.lines[0]?.quantity, 9);
});

test('updateLine removes a line at quantity 0', () => {
  const cart = addLine(emptyCart(), 'knit-black', 1);
  assert.equal(updateLine(cart, 'knit-black', 0).lines.length, 0);
  assert.equal(removeLine(cart, 'knit-black').lines.length, 0);
});

test('TEST10 takes 10 percent and HOOP ships free', () => {
  const subtotal = cartSubtotal([{price: 99, quantity: 1}]);
  const discount = discountAmount(subtotal, 'TEST10');
  assert.equal(subtotal, 99);
  assert.equal(discount, 9.9);
  assert.equal(shippingAmount(subtotal - discount, subtotal), 0);
  assert.equal(cartTotal(subtotal, discount, 0), 89.1);
});

test('strap-only carts pay flat shipping', () => {
  const subtotal = cartSubtotal([{price: 19, quantity: 1}]);
  assert.equal(shippingAmount(subtotal), 8);
  assert.equal(formatMoney(27), '$27');
  assert.equal(formatMoney(89.1), '$89.10');
});

test('test card helpers accept the walkthrough number', () => {
  assert.equal(isTestCardNumber('4242 4242 4242 4242'), true);
  assert.equal(cardLast4('4242 4242 4242 4242'), '4242');
  assert.equal(isExpiryValid('12 / 29', new Date('2026-09-07')), true);
  assert.equal(isExpiryValid('01 / 20', new Date('2026-09-07')), false);
  assert.match(makeOrderId(1_725_000_000_000), /^NB-[A-Z0-9]+$/);
});

test('unknown discount codes do not change the total', () => {
  assert.equal(discountAmount(99, 'NOPE'), 0);
  assert.equal(setDiscount(emptyCart(), 'test10').discountCode, 'TEST10');
});
