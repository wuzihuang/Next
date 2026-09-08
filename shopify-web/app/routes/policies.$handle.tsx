import {useLoaderData} from 'react-router';
import type {Route} from './+types/policies.$handle';
import {PolicyView} from '~/components/shop/SiteViews';
import {localeFromRequest} from '~/lib/locale';
import {readLocale} from '~/lib/localShop.server';
import {getPolicy, policyTitle} from '~/lib/policies';

export const meta: Route.MetaFunction = ({data}) => {
  if (!data) return [{title: 'NEXTBODY'}];
  return [{title: `NEXTBODY · ${policyTitle(data.policy, data.locale)}`}];
};

export async function loader({request, context, params}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const policy = getPolicy(params.handle || '');
  if (!policy) throw new Response(null, {status: 404});
  return {locale, policy};
}

export default function PolicyHandle() {
  const {locale, policy} = useLoaderData<typeof loader>();
  return <PolicyView locale={locale} policy={policy} />;
}
