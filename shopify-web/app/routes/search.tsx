import {useLoaderData} from 'react-router';
import type {Route} from './+types/search';
import {SearchView} from '~/components/shop/SiteViews';
import {searchCatalog} from '~/lib/catalog';
import {localeFromRequest} from '~/lib/locale';
import {readLocale} from '~/lib/localShop.server';

export const meta: Route.MetaFunction = ({data}) => {
  return [{title: data?.locale === 'zh' ? 'NEXTBODY · 搜索' : 'NEXTBODY · Search'}];
};

export async function loader({request, context}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const term = new URL(request.url).searchParams.get('q') || '';
  return {locale, term, products: searchCatalog(term)};
}

export default function SearchPage() {
  const {locale, term, products} = useLoaderData<typeof loader>();
  return <SearchView locale={locale} products={products} term={term} />;
}
