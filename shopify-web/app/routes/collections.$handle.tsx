import {useLoaderData} from 'react-router';
import type {Route} from './+types/collections.$handle';
import {CatalogView} from '~/components/shop/CatalogView';
import {ProductView} from '~/components/shop/ProductView';
import {getCollection, getProduct, productsForCollection} from '~/lib/catalog';
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
    search: Object.fromEntries(new URL(request.url).searchParams),
  };
}

export default function CollectionHandle() {
  const {locale, collection, products, search} = useLoaderData<typeof loader>();
  const hoop = products.length === 1 ? getProduct(products[0].handle) : undefined;
  if (hoop?.handle === 'hoop') {
    return (
      <ProductView
        locale={locale}
        product={hoop}
        search={new URLSearchParams(search)}
      />
    );
  }
  return (
    <CatalogView collection={collection} locale={locale} products={products} />
  );
}
