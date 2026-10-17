import {data, redirect} from 'react-router';
import {
  getShopState,
  isEmail,
  readAccount,
  readCart,
  shopHeaders,
  readLocale,
  writeAccount,
  writeCart,
} from './localShop.server';
import {localeFromRequest} from './locale';
import {shopCopy} from './shopCopy';
import {canonicalVariantId, clampQuantity} from './cartPricing.js';
import {
  addLine,
  emptyCart,
  removeLine,
  setDiscount,
  updateLine,
} from './shopMath';

type ShopContext = {
  session: import('@shopify/hydrogen').HydrogenSession;
  env?: {PUBLIC_STORE_DOMAIN?: string; PUBLIC_HOOP_PRODUCT_HANDLE?: string};
  storefront?: import('@shopify/hydrogen').Storefront;
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
    const notice = code ? 'ok' : '';
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
  const shop = getShopState(context.session, locale);
  if (shop.lines.length === 0) {
    return redirect('/cart');
  }

  try {
    const domain = context.env?.PUBLIC_STORE_DOMAIN || '';
    if (!/^[a-z0-9][a-z0-9-]*\.myshopify\.com$/.test(domain) || !context.storefront) throw new Error('Checkout unavailable');
    const catalog = await context.storefront.query(CHECKOUT_PRODUCT_QUERY, {
      cache: context.storefront.CacheNone(),
      variables: {handle: context.env?.PUBLIC_HOOP_PRODUCT_HANDLE || 'hoop'},
    });
    const variants = catalog.product?.variants.nodes || [];
    const normalizedCart = shop.cart.lines.reduce((cart, line) => addLine(cart, line.variantId, line.quantity), emptyCart());
    const lines = normalizedCart.lines.map((line) => {
      const color = ({'hoop-black': ['black', '黑色'], 'hoop-white': ['white', '白色']} as Record<string, string[]>)[canonicalVariantId(line.variantId)];
      const matches = variants.filter((variant) => color?.includes(variant.title.trim().toLowerCase()));
      const variant = matches[0];
      if (matches.length !== 1 || !variant.availableForSale || variant.price.currencyCode !== 'USD' || Number(variant.price.amount) !== 99 || !/^gid:\/\/shopify\/ProductVariant\/[1-9]\d*$/.test(variant.id)) throw new Error('Item unavailable');
      const quantity = clampQuantity(line.quantity);
      if (!quantity) throw new Error('Invalid quantity');
      return {merchandiseId: variant.id, quantity};
    });
    if (!lines.length) throw new Error('Cart empty');
    const discount = shop.cart.discountCode?.trim();
    const result = await context.storefront.mutate(CHECKOUT_CART_MUTATION, {
      variables: {input: {lines, buyerIdentity: {countryCode: 'US'}, discountCodes: discount ? [discount] : []}},
    });
    if (result.cartCreate?.userErrors.length || result.cartCreate?.warnings.length || !result.cartCreate?.cart) throw new Error('Cart unavailable');
    const createdLines = result.cartCreate.cart.lines.nodes;
    if (createdLines.length !== lines.length || lines.some((line) => !createdLines.some((created) => created.merchandise.id === line.merchandiseId && created.quantity === line.quantity))) throw new Error('Cart changed');
    const url = new URL(result.cartCreate.cart.checkoutUrl);
    const primary = new URL(catalog.shop.primaryDomain.url);
    if (url.protocol !== 'https:' || url.username || url.password || url.port || ![domain, primary.hostname].includes(url.hostname)) throw new Error('Invalid checkout URL');
    // Shopify owns confirmation. Preserve the local cart if checkout is abandoned.
    return redirect(url.toString(), {status: 303, headers: await shopHeaders(context.session, {'Cache-Control': 'no-store'})});
  } catch {
    return data({error: locale === 'zh'
      ? '暂时无法结算：商品缺货、价格变动或商店连接不可用。购物车已保留，请重试或联系 shop@nextbody.ai。'
      : 'Checkout unavailable: stock, price or store connection could not be verified. Your cart is saved. Retry or contact shop@nextbody.ai.'}, {status: 503});
  }
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

const CHECKOUT_PRODUCT_QUERY = `#graphql
  query CheckoutProduct($handle: String!) @inContext(country: US) {
    shop { primaryDomain { url } }
    product(handle: $handle) {
      variants(first: 100) {
        nodes { id title availableForSale price { amount currencyCode } }
      }
    }
  }
` as const;

const CHECKOUT_CART_MUTATION = `#graphql
  mutation CheckoutCart($input: CartInput!) {
    cartCreate(input: $input) {
      cart { id checkoutUrl lines(first: 100) { nodes { quantity merchandise { ... on ProductVariant { id } } } } }
      userErrors { field message code }
      warnings { code }
    }
  }
` as const;
