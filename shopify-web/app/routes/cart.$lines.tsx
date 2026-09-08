import {redirect} from 'react-router';
import type {Route} from './+types/cart.$lines';
import {getVariant} from '~/lib/catalog';
import {readCart, shopHeaders, writeCart} from '~/lib/localShop.server';
import {addLine, emptyCart, setDiscount} from '~/lib/shopMath';

export async function loader({request, context, params}: Route.LoaderArgs) {
  const {lines} = params;
  if (!lines) return redirect('/cart');
  let cart = emptyCart();
  for (const part of lines.split(',')) {
    const [variantId, rawQty] = part.split(':');
    if (!variantId || !getVariant(variantId)) continue;
    cart = addLine(cart, variantId, Number(rawQty || 1));
  }
  const discount = new URL(request.url).searchParams.get('discount');
  if (discount) cart = setDiscount(cart, discount);
  if (cart.lines.length === 0 && readCart(context.session).lines.length) {
    cart = readCart(context.session);
  }
  writeCart(context.session, cart);
  return redirect('/checkout', {headers: await shopHeaders(context.session)});
}

export default function CartPermalink() {
  return null;
}
