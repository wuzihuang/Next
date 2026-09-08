import type {HydrogenSession} from '@shopify/hydrogen';
import {
  emptyCart,
  makeOrderId,
  type CartState,
} from './shopMath';
import {
  hydrateCart,
  totalsForCart,
  type HydratedLine,
  type CartTotals,
} from './catalog';
import type {ShopLocale} from './locale';

const CART_KEY = 'nb_cart';
const ACCOUNT_KEY = 'nb_account';
const ORDERS_KEY = 'nb_orders';
const LOCALE_KEY = 'nb_locale';

export type ShopAccount = {
  email: string;
  name: string;
  phone?: string;
  address1?: string;
  address2?: string;
  city?: string;
  region?: string;
  postal?: string;
  country?: string;
};

export type ShopOrder = {
  id: string;
  email: string;
  name: string;
  createdAt: string;
  lines: HydratedLine[];
  totals: CartTotals;
  discountCode?: string;
  shipping: {
    address1: string;
    address2?: string;
    city: string;
    region: string;
    postal: string;
    country: string;
    phone?: string;
  };
  cardLast4: string;
  status: 'paid_test';
};

export type ShopState = {
  locale: ShopLocale;
  cart: CartState;
  lines: HydratedLine[];
  totals: CartTotals;
  account: ShopAccount | null;
  orders: ShopOrder[];
};

function readJson<T>(session: HydrogenSession, key: string, fallback: T): T {
  const raw = session.get(key);
  if (typeof raw !== 'string' || !raw) return fallback;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

export function readCart(session: HydrogenSession): CartState {
  const cart = readJson<CartState>(session, CART_KEY, emptyCart());
  if (!Array.isArray(cart.lines)) return emptyCart();
  return {
    lines: cart.lines.filter(
      (line) => typeof line?.variantId === 'string' && line.quantity > 0,
    ),
    discountCode: cart.discountCode,
  };
}

export function writeCart(session: HydrogenSession, cart: CartState) {
  session.set(CART_KEY, JSON.stringify(cart));
}

export function readAccount(session: HydrogenSession): ShopAccount | null {
  const account = readJson<ShopAccount | null>(session, ACCOUNT_KEY, null);
  if (!account?.email) return null;
  return account;
}

export function writeAccount(session: HydrogenSession, account: ShopAccount | null) {
  if (!account) {
    session.unset(ACCOUNT_KEY);
    return;
  }
  session.set(ACCOUNT_KEY, JSON.stringify(account));
}

export function readOrders(session: HydrogenSession): ShopOrder[] {
  const orders = readJson<ShopOrder[]>(session, ORDERS_KEY, []);
  return Array.isArray(orders) ? orders : [];
}

export function writeOrders(session: HydrogenSession, orders: ShopOrder[]) {
  session.set(ORDERS_KEY, JSON.stringify(orders.slice(0, 20)));
}

export function readLocale(session: HydrogenSession): string | null {
  const value = session.get(LOCALE_KEY);
  return typeof value === 'string' ? value : null;
}

export function writeLocale(session: HydrogenSession, locale: ShopLocale) {
  session.set(LOCALE_KEY, locale);
}

export function getShopState(session: HydrogenSession, locale: ShopLocale): ShopState {
  const cart = readCart(session);
  return {
    locale,
    cart,
    lines: hydrateCart(cart),
    totals: totalsForCart(cart),
    account: readAccount(session),
    orders: readOrders(session),
  };
}

export async function shopHeaders(
  session: HydrogenSession,
  extra?: HeadersInit,
): Promise<Headers> {
  const headers = new Headers(extra);
  if (session.isPending) {
    headers.append('Set-Cookie', await session.commit());
  }
  return headers;
}

export function createOrder(input: {
  account: ShopAccount;
  cart: CartState;
  cardLast4: string;
}): ShopOrder {
  const lines = hydrateCart(input.cart);
  return {
    id: makeOrderId(),
    email: input.account.email,
    name: input.account.name,
    createdAt: new Date().toISOString(),
    lines,
    totals: totalsForCart(input.cart),
    discountCode: input.cart.discountCode,
    shipping: {
      address1: input.account.address1 || '',
      address2: input.account.address2,
      city: input.account.city || '',
      region: input.account.region || '',
      postal: input.account.postal || '',
      country: input.account.country || '',
      phone: input.account.phone,
    },
    cardLast4: input.cardLast4,
    status: 'paid_test',
  };
}

export function getOrder(session: HydrogenSession, id: string): ShopOrder | undefined {
  return readOrders(session).find((order) => order.id === id);
}

export function isEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim());
}
