import {useLoaderData} from 'react-router';
import type {Route} from './+types/collections.all';
import {CatalogView} from '~/components/shop/CatalogView';
import {getCollection, productsForCollection} from '~/lib/catalog';
import {localeFromRequest} from '~/lib/locale';
import {readLocale} from '~/lib/localShop.server';
export const meta: Route.MetaFunction = ({data}) => {
  const title = data?.locale === 'zh' ? 'NEXTBODY · 商店' : 'NEXTBODY · Shop';
  return [{title}];
};

export async function loader({request, context}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const collection = getCollection('all');
  if (!collection) throw new Response(null, {status: 404});
  return {
    locale,
    collection,
    products: productsForCollection('all'),
  };
}

export default function ShopAll() {
  const {locale, collection, products} = useLoaderData<typeof loader>();
  return (
    <CatalogView collection={collection} locale={locale} products={products} />
  );
}
