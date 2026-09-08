export const SHIPPING_THRESHOLD = 99;
export const SHIPPING_FLAT = 8;
export const TEST_DISCOUNT_CODE = 'TEST10';
export const TEST_DISCOUNT_RATE = 0.1;

export type CartLineInput = {
  variantId: string;
  quantity: number;
};

export type CartState = {
  lines: CartLineInput[];
  discountCode?: string;
};

export function clampQuantity(quantity: number): number {
  if (!Number.isFinite(quantity)) return 1;
  return Math.min(9, Math.max(0, Math.floor(quantity)));
}

export function addLine(
  cart: CartState,
  variantId: string,
  quantity: number,
): CartState {
  const nextQty = clampQuantity(quantity);
  if (nextQty <= 0) return cart;
  const lines = cart.lines.map((line) => ({...line}));
  const existing = lines.find((line) => line.variantId === variantId);
  if (existing) {
    existing.quantity = clampQuantity(existing.quantity + nextQty);
    return {...cart, lines};
  }
  lines.push({variantId, quantity: nextQty});
  return {...cart, lines};
}

export function updateLine(
  cart: CartState,
  variantId: string,
  quantity: number,
): CartState {
  const nextQty = clampQuantity(quantity);
  if (nextQty <= 0) return removeLine(cart, variantId);
  return {
    ...cart,
    lines: cart.lines.map((line) =>
      line.variantId === variantId ? {...line, quantity: nextQty} : line,
    ),
  };
}

export function removeLine(cart: CartState, variantId: string): CartState {
  return {
    ...cart,
    lines: cart.lines.filter((line) => line.variantId !== variantId),
  };
}

export function normalizeDiscountCode(code: string): string {
  return code.trim().toUpperCase();
}

export function isKnownDiscount(code: string): boolean {
  return normalizeDiscountCode(code) === TEST_DISCOUNT_CODE;
}

export function setDiscount(cart: CartState, code: string): CartState {
  const normalized = normalizeDiscountCode(code);
  if (!normalized) {
    const next = {...cart};
    delete next.discountCode;
    return next;
  }
  return {...cart, discountCode: normalized};
}

export function cartQuantity(lines: Array<{quantity: number}>): number {
  return lines.reduce((sum, line) => sum + line.quantity, 0);
}

export function cartSubtotal(
  lines: Array<{price: number; quantity: number}>,
): number {
  return lines.reduce((sum, line) => sum + line.price * line.quantity, 0);
}

export function discountAmount(subtotal: number, code?: string): number {
  if (!code || !isKnownDiscount(code)) return 0;
  return Math.round(subtotal * TEST_DISCOUNT_RATE * 100) / 100;
}

export function shippingAmount(
  afterDiscount: number,
  subtotal = afterDiscount,
): number {
  if (afterDiscount <= 0) return 0;
  return subtotal >= SHIPPING_THRESHOLD ? 0 : SHIPPING_FLAT;
}

export function cartTotal(
  subtotal: number,
  discount: number,
  shipping: number,
): number {
  return Math.max(0, Math.round((subtotal - discount + shipping) * 100) / 100);
}

export function formatMoney(amount: number): string {
  const rounded = Math.round(amount * 100) / 100;
  if (Number.isInteger(rounded)) return `$${rounded}`;
  return `$${rounded.toFixed(2)}`;
}

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

export function emptyCart(): CartState {
  return {lines: []};
}
