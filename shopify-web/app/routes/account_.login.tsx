import {redirect, useActionData, useLoaderData} from 'react-router';
import type {Route} from './+types/account_.login';
import {AccountLoginView} from '~/components/shop/AccountViews';
import {readAccount, readLocale} from '~/lib/localShop.server';
import {localeFromRequest} from '~/lib/locale';
import {handleAccountLogin} from '~/lib/shopActions.server';

export const meta: Route.MetaFunction = ({data}) => {
  return [{title: data?.locale === 'zh' ? 'NEXTBODY · 登录' : 'NEXTBODY · Sign in'}];
};

export async function action({request, context}: Route.ActionArgs) {
  return handleAccountLogin(request, context);
}

export async function loader({request, context}: Route.LoaderArgs) {
  if (readAccount(context.session)) return redirect('/account');
  const locale = localeFromRequest(request, readLocale(context.session));
  return {locale};
}

export default function AccountLogin() {
  const {locale} = useLoaderData<typeof loader>();
  const actionData = useActionData<typeof action>();
  const error =
    actionData && 'error' in actionData ? actionData.error : null;
  return <AccountLoginView error={error} locale={locale} />;
}
