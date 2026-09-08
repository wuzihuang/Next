import assert from 'node:assert/strict';
import test from 'node:test';
import {
  cardLast4, isExpiryValid, isTestCardNumber, isCvcValid, makeOrderId,
} from './shopMath.ts';

test('test checkout accepts the walkthrough card and rejects expired cards', () => {
  assert.equal(isTestCardNumber('4242 4242 4242 4242'), true);
  assert.equal(isTestCardNumber('1234'), false);
  assert.equal(cardLast4('4242 4242 4242 4242'), '4242');
  assert.equal(isExpiryValid('12 / 29', new Date('2026-09-07')), true);
  assert.equal(isExpiryValid('01 / 20', new Date('2026-09-07')), false);
  assert.equal(isCvcValid('123'), true);
  assert.equal(isCvcValid('12'), false);
  assert.match(makeOrderId(1_725_000_000_000), /^NB-[A-Z0-9]+$/);
});
