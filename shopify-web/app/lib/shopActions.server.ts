import {data, redirect} from 'react-router';
import {
  createOrder,
  getShopState,
  isEmail,
  readAccount,
  readCart,
  readOrders,
  shopHeaders,
  readLocale,
  writeAccount,
  writeCart,
  writeOrders,
  type ShopAccount,
} from './localShop.server';
import {localeFromRequest} from './locale';
import {shopCopy} from './shopCopy';
import {
  addLine,
  cardLast4,
  isCvcValid,
  isExpiryValid,
  isKnownDiscount,
  isTestCardNumber,
  removeLine,
  setDiscount,
  updateLine,
} from './shopMath';

type ShopContext = {
  session: import('@shopify/hydrogen').HydrogenSession;
};

function returnTo(request: Request, fallback: string): string {
  const referer = request.headers.get('Referer');
  if (!referer) return fallback;
  try {
    const url = new URL(referer);
    if (url.origin === new URL(request.url).origin) {
      return `${url.pathname}${url.search}`;
    }
  } catch {
    return fallback;
  }
  return fallback;
}

function withCartOpen(path: string, request: Request): string {
  const url = new URL(path, request.url);
  url.searchParams.set('cart', 'open');
  return `${url.pathname}${url.search}`;
}

export async function handleCartAction(
  request: Request,
  context: ShopContext,
) {
  const form = await request.formData();
  const intent = String(form.get('intent') || '');
  const variantId = String(form.get('variantId') || '');
  const quantity = Number(form.get('quantity') || 1);
  let cart = readCart(context.session);

  if (intent === 'add' && variantId) {
    cart = addLine(cart, variantId, quantity);
  } else if (intent === 'update' && variantId) {
    cart = updateLine(cart, variantId, quantity);
  } else if (intent === 'remove' && variantId) {
    cart = removeLine(cart, variantId);
  } else if (intent === 'discount') {
    const code = String(form.get('code') || '');
    cart = setDiscount(cart, code);
    writeCart(context.session, cart);
    const notice = !code ? '' : isKnownDiscount(code) ? 'ok' : 'bad';
    return redirect(notice ? `/cart?code=${notice}` : '/cart', {
      headers: await shopHeaders(context.session),
    });
  }

  writeCart(context.session, cart);
  const headers = await shopHeaders(context.session);
  const redirectTo = String(form.get('redirectTo') || '');
  if (redirectTo === '/checkout') {
    return redirect('/checkout', {headers});
  }
  if (redirectTo.startsWith('/') && !redirectTo.startsWith('//')) {
    return redirect(redirectTo, {headers});
  }
  return redirect(withCartOpen(returnTo(request, '/cart'), request), {headers});
}

export async function handleCheckoutAction(
  request: Request,
  context: ShopContext,
) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const t = shopCopy(locale);
  const shop = getShopState(context.session, locale);
  if (shop.lines.length === 0) {
    return redirect('/cart');
  }

  const form = await request.formData();
  const email = String(form.get('email') || '').trim();
  const name = String(form.get('name') || '').trim();
  const address1 = String(form.get('address1') || '').trim();
  const city = String(form.get('city') || '').trim();
  const region = String(form.get('region') || '').trim();
  const postal = String(form.get('postal') || '').trim();
  const country = String(form.get('country') || '').trim();
  const card = String(form.get('card') || '');
  const expiry = String(form.get('expiry') || '');
  const cvc = String(form.get('cvc') || '');

  let error = '';
  if (!email || !name || !address1 || !city || !region || !postal || !country) {
    error = t.checkout.errorRequired;
  } else if (!isEmail(email)) {
    error = t.checkout.errorEmail;
  } else if (!isTestCardNumber(card)) {
    error = t.checkout.errorCard;
  } else if (!isExpiryValid(expiry)) {
    error = t.checkout.errorExpiry;
  } else if (!isCvcValid(cvc)) {
    error = t.checkout.errorCvc;
  }

  if (error) {
    return data({error}, {status: 400});
  }

  const account: ShopAccount = {
    ...(readAccount(context.session) || {email, name}),
    email,
    name,
    address1,
    address2: String(form.get('address2') || '').trim() || undefined,
    city,
    region,
    postal,
    country,
    phone: String(form.get('phone') || '').trim() || undefined,
  };
  const order = createOrder({
    account,
    cart: shop.cart,
    cardLast4: cardLast4(card),
  });
  writeAccount(context.session, account);
  writeOrders(context.session, [order, ...readOrders(context.session)]);
  writeCart(context.session, {lines: []});
  return redirect(`/checkout/complete?order=${order.id}`, {
    headers: await shopHeaders(context.session),
  });
}

export async function handleAccountLogin(
  request: Request,
  context: ShopContext,
) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const t = shopCopy(locale);
  const form = await request.formData();
  const email = String(form.get('email') || '').trim();
  const name = String(form.get('name') || '').trim();
  if (!isEmail(email)) {
    return data({error: t.checkout.errorEmail}, {status: 400});
  }
  const previous = readAccount(context.session);
  writeAccount(context.session, {
    ...(previous || {email, name}),
    email,
    name: name || previous?.name || email.split('@')[0],
  });
  return redirect('/account', {headers: await shopHeaders(context.session)});
}

export async function handleAccountUpdate(
  request: Request,
  context: ShopContext,
) {
  const current = readAccount(context.session);
  if (!current) return redirect('/account/login');
  const form = await request.formData();
  const email = String(form.get('email') || current.email).trim();
  if (!isEmail(email)) {
    return redirect('/account?saved=0');
  }
  writeAccount(context.session, {
    ...current,
    email,
    name: String(form.get('name') || current.name).trim(),
    address1: String(form.get('address1') || '').trim(),
    city: String(form.get('city') || '').trim(),
    region: String(form.get('region') || '').trim(),
    postal: String(form.get('postal') || '').trim(),
    country: String(form.get('country') || '').trim(),
  });
  return redirect('/account?saved=1', {
    headers: await shopHeaders(context.session),
  });
}
