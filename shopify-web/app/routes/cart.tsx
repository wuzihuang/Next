import {useLoaderData} from 'react-router';
import type {Route} from './+types/cart';
import {CartView, discountNotice} from '~/components/shop/CartView';
import {getShopState, readLocale} from '~/lib/localShop.server';
import {localeFromRequest} from '~/lib/locale';
import {handleCartAction} from '~/lib/shopActions.server';

export const meta: Route.MetaFunction = ({data}) => {
  return [{title: data?.locale === 'zh' ? 'NEXTBODY · 购物车' : 'NEXTBODY · Cart'}];
};

export async function action({request, context}: Route.ActionArgs) {
  return handleCartAction(request, context);
}

export async function loader({request, context}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const notice = new URL(request.url).searchParams.get('code');
  return {
    locale,
    shop: getShopState(context.session, locale),
    notice: discountNotice(notice),
  };
}

export default function CartPage() {
  const {locale, shop, notice} = useLoaderData<typeof loader>();
  return <CartView locale={locale} notice={notice} shop={shop} />;
}
