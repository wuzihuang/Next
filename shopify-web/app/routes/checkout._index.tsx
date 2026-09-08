import {useActionData, useLoaderData} from 'react-router';
import type {Route} from './+types/checkout._index';
import {CheckoutView} from '~/components/shop/CheckoutView';
import {getShopState, readLocale} from '~/lib/localShop.server';
import {localeFromRequest} from '~/lib/locale';
import {handleCheckoutAction} from '~/lib/shopActions.server';

export const meta: Route.MetaFunction = ({data}) => {
  return [{title: data?.locale === 'zh' ? 'NEXTBODY · 结算' : 'NEXTBODY · Checkout'}];
};

export async function action({request, context}: Route.ActionArgs) {
  return handleCheckoutAction(request, context);
}

export async function loader({request, context}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  return {locale, shop: getShopState(context.session, locale)};
}

export default function CheckoutIndex() {
  const {locale, shop} = useLoaderData<typeof loader>();
  const actionData = useActionData<typeof action>();
  const error =
    actionData && 'error' in actionData ? actionData.error : null;
  return <CheckoutView error={error} locale={locale} shop={shop} />;
}
