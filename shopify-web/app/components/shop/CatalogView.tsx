import {Link} from 'react-router';
import type {CatalogCollection, CatalogProduct} from '~/lib/catalog';
import type {ShopLocale} from '~/lib/locale';
import {pickLocale} from '~/lib/locale';
import {shopCopy} from '~/lib/shopCopy';
import {formatMoney} from '~/lib/shopMath';

export function CatalogView({
  locale,
  collection,
  products,
}: {
  locale: ShopLocale;
  collection: CatalogCollection;
  products: CatalogProduct[];
}) {
  const t = shopCopy(locale);
  return (
    <div className="shop-page">
      <section className="shop-hero">
        <div className="shop-hero-copy">
          <p className="shop-kicker">{t.shop.kicker}</p>
          <h1>{pickLocale(locale, collection.title.en, collection.title.zh)}</h1>
          <p className="shop-lede">
            {pickLocale(locale, collection.lede.en, collection.lede.zh)}
          </p>
        </div>
        <div
          className="shop-hero-photo"
          style={{backgroundImage: `url(${collection.image})`}}
        />
      </section>
      <section className="shop-grid-wrap" aria-label={t.nav.shop}>
        {products.length === 0 ? (
          <p className="shop-empty">{t.shop.empty}</p>
        ) : (
          <div className="shop-grid">
            {products.map((product) => (
              <ProductCard key={product.handle} locale={locale} product={product} />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

export function ProductCard({
  locale,
  product,
}: {
  locale: ShopLocale;
  product: CatalogProduct;
}) {
  const t = shopCopy(locale);
  const image = product.variants[0]?.image || product.variants[0]?.images[0];
  return (
    <Link className="shop-card" prefetch="intent" to={`/products/${product.handle}`}>
      <div className="shop-card-media">
        {image ? <img alt="" src={image} /> : null}
      </div>
      <div className="shop-card-copy">
        <span>{pickLocale(locale, product.kicker.en, product.kicker.zh)}</span>
        <strong>{pickLocale(locale, product.title.en, product.title.zh)}</strong>
        <em>
          {t.shop.from} {formatMoney(product.price)}
        </em>
      </div>
    </Link>
  );
}
