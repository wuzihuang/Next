import {useLoaderData} from 'react-router';
import type {Route} from './+types/products.$handle';
import {ProductView} from '~/components/shop/ProductView';
import {getProduct} from '~/lib/catalog';
import {localeFromRequest, pickLocale} from '~/lib/locale';
import {readLocale} from '~/lib/localShop.server';

export const meta: Route.MetaFunction = ({data}) => {
  if (!data) return [{title: 'NEXTBODY'}];
  const title = pickLocale(data.locale, data.product.title.en, data.product.title.zh);
  const description = pickLocale(data.locale, data.product.lede.en, data.product.lede.zh);
  return [{title: `NEXTBODY · ${title}`}, {name: 'description', content: description}];
};

export async function loader({request, context, params}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const product = getProduct(params.handle || '');
  if (!product) throw new Response(null, {status: 404});
  return {
    locale,
    product,
    search: Object.fromEntries(new URL(request.url).searchParams),
  };
}

export default function ProductHandle() {
  const {locale, product, search} = useLoaderData<typeof loader>();
  return (
    <ProductView
      locale={locale}
      product={product}
      search={new URLSearchParams(search)}
    />
  );
}
