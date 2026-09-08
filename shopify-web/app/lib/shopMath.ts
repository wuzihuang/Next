export {
  TEST_DISCOUNT_CODE, addLine, removeLine, updateLine, setDiscount,
  isKnownDiscount, formatMoney, emptyCart,
} from './cartPricing.js';
export type {CartLineInput, CartState} from './cartPricing.js';

export function normalizeCardNumber(value: string): string {
  return value.replace(/\D/g, '');
}

export function isTestCardNumber(value: string): boolean {
  const digits = normalizeCardNumber(value);
  return digits.length >= 13 && digits.length <= 19;
}

export function cardLast4(value: string): string {
  return normalizeCardNumber(value).slice(-4);
}

export function isExpiryValid(value: string, now = new Date()): boolean {
  const match = value.trim().match(/^(\d{1,2})\s*\/\s*(\d{2})$/);
  if (!match) return false;
  const month = Number(match[1]);
  const year = 2000 + Number(match[2]);
  if (month < 1 || month > 12) return false;
  const expiry = new Date(year, month);
  return expiry > now;
}

export function isCvcValid(value: string): boolean {
  return /^\d{3,4}$/.test(value.trim());
}

export function makeOrderId(now = Date.now()): string {
  return `NB-${now.toString(36).toUpperCase().slice(-6)}`;
}

