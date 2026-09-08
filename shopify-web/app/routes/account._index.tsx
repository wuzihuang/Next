import {redirect, useLoaderData} from 'react-router';
import type {Route} from './+types/account._index';
import {AccountHomeView} from '~/components/shop/AccountViews';
import {
  readAccount,
  readLocale,
  readOrders,
} from '~/lib/localShop.server';
import {localeFromRequest} from '~/lib/locale';
import {handleAccountUpdate} from '~/lib/shopActions.server';

export const meta: Route.MetaFunction = ({data}) => {
  return [{title: data?.locale === 'zh' ? 'NEXTBODY · 账户' : 'NEXTBODY · Account'}];
};

export async function action({request, context}: Route.ActionArgs) {
  return handleAccountUpdate(request, context);
}

export async function loader({request, context}: Route.LoaderArgs) {
  const account = readAccount(context.session);
  if (!account) return redirect('/account/login');
  const locale = localeFromRequest(request, readLocale(context.session));
  return {
    locale,
    account,
    orders: readOrders(context.session),
    saved: new URL(request.url).searchParams.get('saved') === '1',
  };
}

export default function AccountIndex() {
  const {locale, account, orders, saved} = useLoaderData<typeof loader>();
  return (
    <AccountHomeView
      account={account}
      locale={locale}
      orders={orders}
      saved={saved}
    />
  );
}
