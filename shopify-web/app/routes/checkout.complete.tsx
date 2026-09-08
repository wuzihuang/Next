import {redirect, useLoaderData} from 'react-router';
import type {Route} from './+types/checkout.complete';
import {CompleteView} from '~/components/shop/CheckoutView';
import {getOrder, readLocale} from '~/lib/localShop.server';
import {localeFromRequest} from '~/lib/locale';

export const meta: Route.MetaFunction = ({data}) => {
  return [
    {
      title:
        data?.locale === 'zh' ? 'NEXTBODY · 测试订单' : 'NEXTBODY · Test order',
    },
  ];
};

export async function loader({request, context}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const id = new URL(request.url).searchParams.get('order') || '';
  const order = getOrder(context.session, id);
  if (!order) return redirect('/cart');
  return {locale, order};
}

export default function CheckoutComplete() {
  const {locale, order} = useLoaderData<typeof loader>();
  return <CompleteView locale={locale} order={order} />;
}
