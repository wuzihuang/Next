import {redirect} from 'react-router';
import type {Route} from './+types/discount.$code';
import {readCart, shopHeaders, writeCart} from '~/lib/localShop.server';
import {isKnownDiscount, setDiscount} from '~/lib/shopMath';

export async function loader({request, context, params}: Route.LoaderArgs) {
  const url = new URL(request.url);
  let redirectParam = url.searchParams.get('redirect') || '/cart';
  if (redirectParam.includes('//')) redirectParam = '/cart';
  const cart = setDiscount(readCart(context.session), params.code || '');
  writeCart(context.session, cart);
  const notice = params.code && isKnownDiscount(params.code) ? 'ok' : 'bad';
  const dest = redirectParam.startsWith('/cart')
    ? `/cart?code=${notice}`
    : redirectParam;
  return redirect(dest, {headers: await shopHeaders(context.session)});
}
