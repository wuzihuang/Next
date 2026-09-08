import {useLoaderData} from 'react-router';
import type {Route} from './+types/policies._index';
import {PolicyIndexView} from '~/components/shop/SiteViews';
import {localeFromRequest} from '~/lib/locale';
import {readLocale} from '~/lib/localShop.server';
import {POLICIES} from '~/lib/policies';

export const meta: Route.MetaFunction = ({data}) => {
  return [{title: data?.locale === 'zh' ? 'NEXTBODY · 法律' : 'NEXTBODY · Policies'}];
};

export async function loader({request, context}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  return {locale, policies: POLICIES};
}

export default function PoliciesIndex() {
  const {locale, policies} = useLoaderData<typeof loader>();
  return <PolicyIndexView locale={locale} policies={policies} />;
}
