import {Form, Link, useLocation} from 'react-router';
import {
  defaultSelection,
  findVariant,
  type CatalogProduct,
} from '~/lib/catalog';
import type {ShopLocale} from '~/lib/locale';
import {pickLocale} from '~/lib/locale';
import {shopCopy} from '~/lib/shopCopy';
import {formatMoney} from '~/lib/shopMath';

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
  const finish = selected.finish || variant.options.finish;
  const includes = pickLocale(locale, product.includes.en, product.includes.zh);

  return (
    <div className="shop-page shop-pdp kit-page">
      <section className="kit">
        <div className="kit-well">
          <img alt="" className="kit-hero" src={activeImage} />
          <div className="kit-thumbs">
            {images.map((image) => (
              <Link
                key={image}
                className={image === activeImage ? 'is-on' : undefined}
                preventScrollReset
                replace
                to={`${location.pathname}?${nextParams(search, {img: image})}`}
              >
                <img alt="" src={image} />
              </Link>
            ))}
          </div>
        </div>
        <aside className="kit-box">
          <p className="kit-eye">
            {pickLocale(locale, product.kicker.en, product.kicker.zh)}
          </p>
          <h1 className="kit-title">
            {pickLocale(locale, product.title.en, product.title.zh)}
          </h1>
          <p className="kit-price">
            <span className="kit-price-mark">$</span>
            {product.price}
          </p>
          <p className="kit-lede">
            {pickLocale(locale, product.lede.en, product.lede.zh)}
          </p>
          <Form className="kit-form" id="pdp-cart" method="post" action="/cart">
            <input type="hidden" name="intent" value="add" />
            <input type="hidden" name="variantId" value={variant.id} />
            <input type="hidden" name="quantity" value="1" />
            {product.options.map((option) => (
              <fieldset key={option.id} className="kit-option">
                <legend>{pickLocale(locale, option.name.en, option.name.zh)}</legend>
                <div className="kit-swatches">
                  {option.values.map((value) => {
                    const next = {...selected, [option.id]: value.id};
                    const href = `${location.pathname}?${nextParams(search, {
                      ...next,
                      img: '',
                    })}`;
                    const on = selected[option.id] === value.id;
                    return (
                      <Link
                        key={value.id}
                        className={on ? 'is-on' : undefined}
                        preventScrollReset
                        replace
                        to={href}
                      >
                        <i className={`kit-dot kit-dot-${value.id}`} />
                        {pickLocale(locale, value.label.en, value.label.zh)}
                      </Link>
                    );
                  })}
                </div>
              </fieldset>
            ))}
            <div className="kit-include">
              <p>{t.product.inBox}</p>
              <ul>
                {includes.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </div>
            <div className="kit-actions">
              <button className="kit-btn" type="submit">
                {variant.available ? t.product.add : t.product.soldOut}
              </button>
              <button
                className="kit-btn kit-btn-lime"
                name="redirectTo"
                type="submit"
                value="/checkout"
              >
                {t.product.buy}
              </button>
            </div>
          </Form>
          <p className="kit-ship">
            <b>{t.product.shipping}</b>
            <span>{t.product.shippingNote}</span>
          </p>
          <div className="kit-facts">
            {product.facts.map((fact) => (
              <div key={fact.label.en}>
                <strong>{pickLocale(locale, fact.value.en, fact.value.zh)}</strong>
                <span>{pickLocale(locale, fact.label.en, fact.label.zh)}</span>
              </div>
            ))}
          </div>
          <div className="kit-body">
            {pickLocale(locale, product.description.en, product.description.zh).map(
              (para) => (
                <p key={para}>{para}</p>
              ),
            )}
            <p className="kit-legal">{t.product.legal}</p>
          </div>
        </aside>
      </section>
      <div className="kit-dock">
        <p>
          <span>
            {pickLocale(locale, product.title.en, product.title.zh)}
            {finish ? ` · ${finishLabel(product, finish, locale)}` : ''}
          </span>
          <strong>{formatMoney(product.price)}</strong>
        </p>
        <button
          className="kit-btn"
          disabled={!variant.available}
          form="pdp-cart"
          type="submit"
        >
          {variant.available ? t.product.add : t.product.soldOut}
        </button>
        <button
          className="kit-btn kit-btn-lime"
          disabled={!variant.available}
          form="pdp-cart"
          name="redirectTo"
          type="submit"
          value="/checkout"
        >
          {t.product.buy}
        </button>
      </div>
    </div>
  );
}

function finishLabel(
  product: CatalogProduct,
  finish: string,
  locale: ShopLocale,
): string {
  const option = product.options.find((item) => item.id === 'finish');
  const value = option?.values.find((item) => item.id === finish);
  return value ? pickLocale(locale, value.label.en, value.label.zh) : finish;
}

function nextParams(
  search: URLSearchParams,
  patch: Record<string, string>,
): string {
  const next = new URLSearchParams(search);
  for (const [key, value] of Object.entries(patch)) {
    if (value) next.set(key, value);
    else next.delete(key);
  }
  return next.toString();
}
