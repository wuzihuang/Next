import {Form, Link} from 'react-router';
import type {ShopLocale} from '~/lib/locale';
import {pickLocale} from '~/lib/locale';
import type {ShopAccount, ShopOrder} from '~/lib/localShop.server';
import {shopCopy} from '~/lib/shopCopy';
import {formatMoney} from '~/lib/shopMath';

export function AccountLoginView({
  locale,
  error,
}: {
  locale: ShopLocale;
  error?: string | null;
}) {
  const t = shopCopy(locale);
  return (
    <div className="shop-page shop-account">
      <h1>{t.account.title}</h1>
      <p className="shop-lede">{t.account.lede}</p>
      {error ? <p className="shop-note is-bad">{error}</p> : null}
      <Form className="shop-account-form" method="post">
        <label>
          {t.account.email}
          <input autoComplete="email" name="email" required type="email" />
        </label>
        <label>
          {t.account.name}
          <input autoComplete="name" name="name" type="text" />
        </label>
        <button className="lp-pill lp-pill-lime" type="submit">
          {t.account.enter}
        </button>
      </Form>
    </div>
  );
}

export function AccountHomeView({
  locale,
  account,
  orders,
  saved,
}: {
  locale: ShopLocale;
  account: ShopAccount;
  orders: ShopOrder[];
  saved?: boolean;
}) {
  const t = shopCopy(locale);
  return (
    <div className="shop-page shop-account">
      <div className="shop-account-head">
        <div>
          <p className="shop-kicker">{t.account.welcome}</p>
          <h1>{account.name || account.email}</h1>
          <p className="shop-hint">{t.account.testNote}</p>
        </div>
        <Form method="post" action="/account/logout">
          <button className="shop-text-btn" type="submit">
            {t.account.signOut}
          </button>
        </Form>
      </div>
      {saved ? <p className="shop-note is-ok">{t.account.saved}</p> : null}
      <section className="shop-account-block">
        <h2>{t.account.orders}</h2>
        {orders.length === 0 ? (
          <p className="shop-lede">{t.account.noOrders}</p>
        ) : (
          <ul className="shop-order-list">
            {orders.map((order) => (
              <li key={order.id}>
                <Link prefetch="intent" to={`/account/orders/${order.id}`}>
                  <strong>{order.id}</strong>
                  <span>{new Date(order.createdAt).toLocaleDateString()}</span>
                  <em>{formatMoney(order.totals.total)}</em>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
      <Form className="shop-account-form" method="post">
        <h2>{t.account.profile}</h2>
        <input name="intent" type="hidden" value="profile" />
        <label>
          {t.account.email}
          <input
            autoComplete="email"
            defaultValue={account.email}
            name="email"
            required
            type="email"
          />
        </label>
        <label>
          {t.account.name}
          <input
            autoComplete="name"
            defaultValue={account.name}
            name="name"
            type="text"
          />
        </label>
        <h2>{t.account.addresses}</h2>
        <label>
          {shopCopy(locale).checkout.address1}
          <input defaultValue={account.address1 || ''} name="address1" type="text" />
        </label>
        <label>
          {shopCopy(locale).checkout.city}
          <input defaultValue={account.city || ''} name="city" type="text" />
        </label>
        <div className="shop-split">
          <label>
            {shopCopy(locale).checkout.region}
            <input defaultValue={account.region || ''} name="region" type="text" />
          </label>
          <label>
            {shopCopy(locale).checkout.postal}
            <input defaultValue={account.postal || ''} name="postal" type="text" />
          </label>
        </div>
        <label>
          {shopCopy(locale).checkout.country}
          <input defaultValue={account.country || ''} name="country" type="text" />
        </label>
        <button className="lp-pill" type="submit">
          {t.account.save}
        </button>
      </Form>
    </div>
  );
}

export function AccountOrderView({
  locale,
  order,
}: {
  locale: ShopLocale;
  order: ShopOrder;
}) {
  const t = shopCopy(locale);
  return (
    <div className="shop-page">
      <p className="shop-kicker">{t.account.orderPaid}</p>
      <h1>{order.id}</h1>
      <p className="shop-lede">
        {order.name} · {order.email}
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
        {t.cart.total} {formatMoney(order.totals.total)}
      </p>
      <Link className="shop-text-btn" prefetch="intent" to="/account">
        ← {t.account.title}
      </Link>
    </div>
  );
}
