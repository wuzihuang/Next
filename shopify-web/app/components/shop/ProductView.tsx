import {Form, Link, useLocation} from 'react-router';
import {
  defaultSelection,
  findVariant,
  relatedProducts,
  type CatalogProduct,
} from '~/lib/catalog';
import type {ShopLocale} from '~/lib/locale';
import {pickLocale} from '~/lib/locale';
import {shopCopy} from '~/lib/shopCopy';
import {formatMoney} from '~/lib/shopMath';
import {ProductCard} from './CatalogView';

export function ProductView({
  locale,
  product,
  search,
}: {
  locale: ShopLocale;
  product: CatalogProduct;
  search: URLSearchParams;
}) {
  const t = shopCopy(locale);
  const location = useLocation();
  const selected = {...defaultSelection(product)};
  for (const option of product.options) {
    const value = search.get(option.id);
    if (value && option.values.some((item) => item.id === value)) {
      selected[option.id] = value;
    }
  }
  const variant = findVariant(product, selected) ?? product.variants[0];
  const images = variant?.images?.length ? variant.images : [variant?.image];
  const activeImage = search.get('img') || images[0];
  const related = relatedProducts(product.handle);

  return (
    <div className="shop-page shop-pdp">
      <section className="pdp">
        <div className="pdp-gallery">
          <div
            className="pdp-hero-shot"
            style={{backgroundImage: `url(${activeImage})`}}
          />
          <div className="pdp-thumbs">
            {images.map((image) => (
              <Link
                key={image}
                className={image === activeImage ? 'is-on' : undefined}
                preventScrollReset
                replace
                to={`${location.pathname}?${nextParams(search, {img: image})}`}
              >
                <span style={{backgroundImage: `url(${image})`}} />
              </Link>
            ))}
          </div>
        </div>
        <div className="pdp-buy">
          <p className="shop-kicker">
            {pickLocale(locale, product.kicker.en, product.kicker.zh)}
          </p>
          <h1>{pickLocale(locale, product.title.en, product.title.zh)}</h1>
          <p className="pdp-price">{formatMoney(product.price)}</p>
          <p className="shop-lede">
            {pickLocale(locale, product.lede.en, product.lede.zh)}
          </p>
          <Form className="pdp-form" id="pdp-cart" method="post" action="/cart">
            <input type="hidden" name="intent" value="add" />
            <input type="hidden" name="variantId" value={variant.id} />
            <input type="hidden" name="quantity" value="1" />
            {product.options.map((option) => (
              <fieldset key={option.id} className="pdp-option">
                <legend>{pickLocale(locale, option.name.en, option.name.zh)}</legend>
                <div className="pdp-swatches">
                  {option.values.map((value) => {
                    const next = {...selected, [option.id]: value.id};
                    const href = `${location.pathname}?${nextParams(search, next)}`;
                    const on = selected[option.id] === value.id;
                    return (
                      <Link
                        key={value.id}
                        className={on ? 'is-on' : undefined}
                        preventScrollReset
                        replace
                        to={href}
                      >
                        {pickLocale(locale, value.label.en, value.label.zh)}
                      </Link>
                    );
                  })}
                </div>
              </fieldset>
            ))}
            <div className="pdp-actions">
              <button className="lp-pill" type="submit">
                {variant.available ? t.product.add : t.product.soldOut}
              </button>
              <button
                className="lp-pill lp-pill-lime"
                name="redirectTo"
                type="submit"
                value="/checkout"
              >
                {t.product.buy}
              </button>
            </div>
          </Form>
          <div className="pdp-sticky-buy">
            <p>
              <span>{pickLocale(locale, product.title.en, product.title.zh)}</span>
              <strong>{formatMoney(product.price)}</strong>
            </p>
            <button
              className="lp-pill"
              disabled={!variant.available}
              form="pdp-cart"
              type="submit"
            >
              {variant.available ? t.product.add : t.product.soldOut}
            </button>
            <button
              className="lp-pill lp-pill-lime"
              disabled={!variant.available}
              form="pdp-cart"
              name="redirectTo"
              type="submit"
              value="/checkout"
            >
              {t.product.buy}
            </button>
          </div>
          <p className="pdp-ship">
            <b>{t.product.shipping}</b>
            <span>{t.product.shippingNote}</span>
          </p>
          <div className="pdp-facts">
            {product.facts.map((fact) => (
              <div key={fact.label.en}>
                <strong>{pickLocale(locale, fact.value.en, fact.value.zh)}</strong>
                <span>{pickLocale(locale, fact.label.en, fact.label.zh)}</span>
              </div>
            ))}
          </div>
          <div className="pdp-body">
            {pickLocale(locale, product.description.en, product.description.zh).map(
              (para) => (
                <p key={para}>{para}</p>
              ),
            )}
            <p className="pdp-legal">{t.product.legal}</p>
          </div>
        </div>
      </section>
      {related.length ? (
        <section className="shop-related">
          <h2>{t.product.related}</h2>
          <div className="shop-grid">
            {related.map((item) => (
              <ProductCard key={item.handle} locale={locale} product={item} />
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}

function nextParams(
  search: URLSearchParams,
  patch: Record<string, string>,
): string {
  const next = new URLSearchParams(search);
  for (const [key, value] of Object.entries(patch)) {
    next.set(key, value);
  }
  return next.toString();
}
