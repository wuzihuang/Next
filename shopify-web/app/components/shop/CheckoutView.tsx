import {Form, Link} from 'react-router';
import type {ShopLocale} from '~/lib/locale';
import {pickLocale} from '~/lib/locale';
import type {ShopOrder, ShopState} from '~/lib/localShop.server';
import {shopCopy} from '~/lib/shopCopy';
import {formatMoney} from '~/lib/shopMath';

export function CheckoutView({
  locale,
  shop,
  error,
}: {
  locale: ShopLocale;
  shop: ShopState;
  error?: string | null;
}) {
  const t = shopCopy(locale);
  const account = shop.account;
  if (shop.lines.length === 0) {
    return (
      <div className="shop-page">
        <h1>{t.checkout.title}</h1>
        <p className="shop-lede">{t.checkout.empty}</p>
        <Link className="lp-pill lp-pill-lime" prefetch="intent" to="/products/hoop">
          {t.cart.continue}
        </Link>
      </div>
    );
  }

  return (
    <div className="shop-page shop-checkout">
      <h1>{t.checkout.title}</h1>
      <p className="shop-banner">{t.checkout.testBanner}</p>
      {error ? <p className="shop-note is-bad">{error}</p> : null}
      <div className="shop-checkout-grid">
        <Form className="shop-checkout-form" method="post">
          <fieldset>
            <legend>{t.checkout.contact}</legend>
            <label>
              {t.checkout.email}
              <input
                autoComplete="email"
                defaultValue={account?.email || ''}
                name="email"
                required
                type="email"
              />
            </label>
            <label>
              {t.checkout.name}
              <input
                autoComplete="name"
                defaultValue={account?.name || ''}
                name="name"
                required
                type="text"
              />
            </label>
          </fieldset>
          <fieldset>
            <legend>{t.checkout.shipping}</legend>
            <label>
              {t.checkout.address1}
              <input
                autoComplete="address-line1"
                defaultValue={account?.address1 || ''}
                name="address1"
                required
                type="text"
              />
            </label>
            <label>
              {t.checkout.address2}
              <input
                autoComplete="address-line2"
                defaultValue={account?.address2 || ''}
                name="address2"
                type="text"
              />
            </label>
            <div className="shop-split">
              <label>
                {t.checkout.city}
                <input
                  autoComplete="address-level2"
                  defaultValue={account?.city || ''}
                  name="city"
                  required
                  type="text"
                />
              </label>
              <label>
                {t.checkout.region}
                <input
                  autoComplete="address-level1"
                  defaultValue={account?.region || ''}
                  name="region"
                  required
                  type="text"
                />
              </label>
            </div>
            <div className="shop-split">
              <label>
                {t.checkout.postal}
                <input
                  autoComplete="postal-code"
                  defaultValue={account?.postal || ''}
                  name="postal"
                  required
                  type="text"
                />
              </label>
              <label>
                {t.checkout.country}
                <select
                  defaultValue={account?.country || t.checkout.countries[0].id}
                  name="country"
                >
                  {t.checkout.countries.map((country) => (
                    <option key={country.id} value={country.id}>
                      {country.label}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <label>
              {t.checkout.phone}
              <input
                autoComplete="tel"
                defaultValue={account?.phone || ''}
                name="phone"
                type="tel"
              />
            </label>
          </fieldset>
          <fieldset>
            <legend>{t.checkout.payment}</legend>
            <label>
              {t.checkout.card}
              <input
                autoComplete="cc-number"
                defaultValue="4242 4242 4242 4242"
                inputMode="numeric"
                name="card"
                placeholder="4242 4242 4242 4242"
                required
              />
            </label>
            <p className="shop-hint">{t.checkout.cardHint}</p>
            <div className="shop-split">
              <label>
                {t.checkout.expiry}
                <input
                  autoComplete="cc-exp"
                  defaultValue="12 / 29"
                  name="expiry"
                  placeholder="12 / 29"
                  required
                />
              </label>
              <label>
                {t.checkout.cvc}
                <input
                  autoComplete="cc-csc"
                  defaultValue="123"
                  inputMode="numeric"
                  name="cvc"
                  required
                />
              </label>
            </div>
          </fieldset>
          <button className="lp-pill lp-pill-lime shop-place" type="submit">
            {t.checkout.place} · {formatMoney(shop.totals.total)}
          </button>
        </Form>
        <aside className="shop-summary">
          <ul className="shop-mini-lines">
            {shop.lines.map((line) => (
              <li key={line.variantId}>
                <span className="shop-mini-media">
              <img alt="" src={line.image} />
            </span>
                <div>
                  <strong>
                    {pickLocale(locale, line.productTitle.en, line.productTitle.zh)}
                  </strong>
                  <span>
                    {pickLocale(locale, line.variantLabel.en, line.variantLabel.zh)} ×{' '}
                    {line.quantity}
                  </span>
                </div>
                <em>{formatMoney(line.price * line.quantity)}</em>
              </li>
            ))}
          </ul>
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
        </aside>
      </div>
    </div>
  );
}

export function CompleteView({
  locale,
  order,
}: {
  locale: ShopLocale;
  order: ShopOrder;
}) {
  const t = shopCopy(locale);
  return (
    <div className="shop-page shop-complete">
      <p className="shop-kicker">{t.complete.kicker}</p>
      <h1>{t.complete.title}</h1>
      <p className="shop-lede">{t.complete.lede}</p>
      <p className="shop-order-id">
        {t.complete.order} {order.id}
      </p>
      <p className="shop-hint">
        {t.complete.test} ···{order.cardLast4}
      </p>
      <ul className="shop-mini-lines">
        {order.lines.map((line) => (
          <li key={line.variantId}>
            <span className="shop-mini-media">
              <img alt="" src={line.image} />
            </span>
            <div>
              <strong>
                {pickLocale(locale, line.productTitle.en, line.productTitle.zh)}
              </strong>
              <span>
                {pickLocale(locale, line.variantLabel.en, line.variantLabel.zh)} ×{' '}
                {line.quantity}
              </span>
            </div>
            <em>{formatMoney(line.price * line.quantity)}</em>
          </li>
        ))}
      </ul>
      <p className="shop-complete-total">
        <span>{t.cart.total}</span>
        <b>{formatMoney(order.totals.total)}</b>
      </p>
      <div className="pdp-actions">
        <Link className="lp-pill" prefetch="intent" to="/collections/all">
          {t.complete.continue}
        </Link>
        <Link className="lp-pill lp-pill-lime" prefetch="intent" to="/account">
          {t.complete.account}
        </Link>
      </div>
    </div>
  );
}
