import {Link, useLoaderData} from 'react-router';
import type {Route} from './+types/collections._index';
import {COLLECTIONS} from '~/lib/catalog';
import {localeFromRequest, pickLocale} from '~/lib/locale';
import {readLocale} from '~/lib/localShop.server';
import {shopCopy} from '~/lib/shopCopy';

export const meta: Route.MetaFunction = ({data}) => {
  return [{title: data?.locale === 'zh' ? 'NEXTBODY · 系列' : 'NEXTBODY · Collections'}];
};

export async function loader({request, context}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  return {locale, collections: COLLECTIONS};
}

export default function CollectionsIndex() {
  const {locale, collections} = useLoaderData<typeof loader>();
  const t = shopCopy(locale);
  return (
    <div className="shop-page">
      <h1>{t.nav.shop}</h1>
      <div className="shop-grid">
        {collections.map((collection) => (
          <Link
            className="shop-card"
            key={collection.handle}
            prefetch="intent"
            to={`/collections/${collection.handle}`}
          >
            <div
              className="shop-card-media"
              style={{backgroundImage: `url(${collection.image})`}}
            />
            <div className="shop-card-copy">
              <strong>
                {pickLocale(locale, collection.title.en, collection.title.zh)}
              </strong>
              <em>{pickLocale(locale, collection.lede.en, collection.lede.zh)}</em>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
