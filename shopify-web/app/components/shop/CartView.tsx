import {Form, Link} from 'react-router';
import type {HydratedLine} from '~/lib/catalog';
import type {ShopLocale} from '~/lib/locale';
import {pickLocale} from '~/lib/locale';
import type {ShopState} from '~/lib/localShop.server';
import {shopCopy} from '~/lib/shopCopy';
import {formatMoney, isKnownDiscount} from '~/lib/shopMath';

export function CartView({
  locale,
  shop,
  layout = 'page',
  notice,
}: {
  locale: ShopLocale;
  shop: ShopState;
  layout?: 'page' | 'aside';
  notice?: string | null;
}) {
  const t = shopCopy(locale);
  const empty = shop.lines.length === 0;
  return (
    <div className={layout === 'aside' ? 'shop-cart is-aside' : 'shop-cart shop-page'}>
      {layout === 'page' ? <h1>{t.cart.title}</h1> : null}
      {notice === 'ok' ? <p className="shop-note is-ok">{t.cart.codeOk}</p> : null}
      {notice === 'bad' ? <p className="shop-note is-bad">{t.cart.codeBad}</p> : null}
      {empty ? (
        <div className="shop-empty-block">
          <p>{t.cart.empty}</p>
          <Link className="lp-pill lp-pill-lime" prefetch="intent" to="/products/hoop">
            {t.cart.continue}
          </Link>
        </div>
      ) : (
        <div className="shop-cart-grid">
          <ul className="shop-lines">
            {shop.lines.map((line) => (
              <CartLineRow key={line.variantId} locale={locale} line={line} />
            ))}
          </ul>
          <aside className="shop-summary">
            <Form className="shop-code" method="post" action="/cart">
              <input type="hidden" name="intent" value="discount" />
              <label htmlFor="discount-code">{t.cart.code}</label>
              <div>
                <input
                  defaultValue={shop.cart.discountCode || ''}
                  id="discount-code"
                  name="code"
                  placeholder={t.cart.codeHint}
                  type="text"
                />
                <button className="lp-pill" type="submit">
                  {t.cart.apply}
                </button>
              </div>
            </Form>
            <dl>
              <div>
                <dt>{t.cart.subtotal}</dt>
                <dd>{formatMoney(shop.totals.subtotal)}</dd>
              </div>
              {shop.totals.discount > 0 ? (
                <div>
                  <dt>{t.cart.discount}</dt>
                  <dd>−{formatMoney(shop.totals.discount)}</dd>
                </div>
              ) : null}
              <div>
                <dt>{t.cart.shipping}</dt>
                <dd>
                  {shop.totals.shipping === 0
                    ? t.cart.shippingFree
                    : formatMoney(shop.totals.shipping)}
                </dd>
              </div>
              <div className="is-total">
                <dt>{t.cart.total}</dt>
                <dd>{formatMoney(shop.totals.total)}</dd>
              </div>
            </dl>
            <Link className="lp-pill lp-pill-lime" prefetch="intent" to="/checkout">
              {t.cart.checkout}
            </Link>
          </aside>
        </div>
      )}
    </div>
  );
}

function CartLineRow({
  locale,
  line,
}: {
  locale: ShopLocale;
  line: HydratedLine;
}) {
  const t = shopCopy(locale);
  return (
    <li className="shop-line">
      <Link
        className="shop-line-media"
        prefetch="intent"
        to={`/products/${line.productHandle}`}
      >
        <img alt="" src={line.image} />
      </Link>
      <div className="shop-line-copy">
        <strong>{pickLocale(locale, line.productTitle.en, line.productTitle.zh)}</strong>
        <span>{pickLocale(locale, line.variantLabel.en, line.variantLabel.zh)}</span>
        <em>{formatMoney(line.price)}</em>
        <div className="shop-line-ops">
          <Form method="post" action="/cart">
            <input type="hidden" name="intent" value="update" />
            <input type="hidden" name="variantId" value={line.variantId} />
            <label className="sr-only" htmlFor={`qty-${line.variantId}`}>
              {t.cart.qty}
            </label>
            <select
              defaultValue={String(line.quantity)}
              id={`qty-${line.variantId}`}
              name="quantity"
              onChange={(event) => event.currentTarget.form?.requestSubmit()}
            >
              {Array.from({length: 9}, (_, index) => index + 1).map((qty) => (
                <option key={qty} value={qty}>
                  {qty}
                </option>
              ))}
            </select>
          </Form>
          <Form method="post" action="/cart">
            <input type="hidden" name="intent" value="remove" />
            <input type="hidden" name="variantId" value={line.variantId} />
            <button className="shop-text-btn" type="submit">
              {t.cart.remove}
            </button>
          </Form>
        </div>
      </div>
    </li>
  );
}

export function discountNotice(code: string | null): string | null {
  if (!code) return null;
  return isKnownDiscount(code) ? 'ok' : 'bad';
}
