import {redirect, useLoaderData} from 'react-router';
import type {Route} from './+types/account.orders.$id';
import {AccountOrderView} from '~/components/shop/AccountViews';
import {getOrder, readLocale} from '~/lib/localShop.server';
import {localeFromRequest} from '~/lib/locale';

export const meta: Route.MetaFunction = ({data}) => {
  return [{title: data ? `NEXTBODY · ${data.order.id}` : 'NEXTBODY'}];
};

export async function loader({request, context, params}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const order = getOrder(context.session, params.id || '');
  if (!order) return redirect('/account');
  return {locale, order};
}

export default function AccountOrder() {
  const {locale, order} = useLoaderData<typeof loader>();
  return <AccountOrderView locale={locale} order={order} />;
}
