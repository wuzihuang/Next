import {useLoaderData} from 'react-router';
import type {Route} from './+types/collections.$handle';
import {CatalogView} from '~/components/shop/CatalogView';
import {getCollection, productsForCollection} from '~/lib/catalog';
import {localeFromRequest, pickLocale} from '~/lib/locale';
import {readLocale} from '~/lib/localShop.server';

export const meta: Route.MetaFunction = ({data}) => {
  const title = data
    ? pickLocale(data.locale, data.collection.title.en, data.collection.title.zh)
    : 'Shop';
  return [{title: `NEXTBODY · ${title}`}];
};

export async function loader({request, context, params}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const handle = params.handle || 'all';
  const collection = getCollection(handle);
  if (!collection) throw new Response(null, {status: 404});
  return {
    locale,
    collection,
    products: productsForCollection(handle),
  };
}

export default function CollectionHandle() {
  const {locale, collection, products} = useLoaderData<typeof loader>();
  return (
    <CatalogView collection={collection} locale={locale} products={products} />
  );
}
