import {useLoaderData} from 'react-router';
import type {Route} from './+types/collections.all';
import {ProductView} from '~/components/shop/ProductView';
import {getProduct} from '~/lib/catalog';
import {localeFromRequest} from '~/lib/locale';
import {readLocale} from '~/lib/localShop.server';

export const meta: Route.MetaFunction = ({data}) => {
  const title = data?.locale === 'zh' ? 'NEXTBODY · HOOP' : 'NEXTBODY · HOOP';
  return [{title}];
};

export async function loader({request, context}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const product = getProduct('hoop');
  if (!product) throw new Response(null, {status: 404});
  return {
    locale,
    product,
    search: Object.fromEntries(new URL(request.url).searchParams),
  };
}

export default function ShopAll() {
  const {locale, product, search} = useLoaderData<typeof loader>();
  return (
    <ProductView
      locale={locale}
      product={product}
      search={new URLSearchParams(search)}
    />
  );
}
