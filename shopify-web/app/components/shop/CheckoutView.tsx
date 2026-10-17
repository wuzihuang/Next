import {Form, Link} from 'react-router';
import type {ShopLocale} from '~/lib/locale';
import {pickLocale} from '~/lib/locale';
import type {ShopState} from '~/lib/localShop.server';
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
      <p className="shop-banner">{locale === 'zh' ? '由 Shopify 处理支付与订单。' : 'Payment and orders are handled by Shopify.'}</p>
      {error ? <p className="shop-note is-bad">{error}</p> : null}
      <div className="shop-checkout-grid">
        <Form className="shop-checkout-form" method="post">
          <p>{locale === 'zh' ? '地址和支付信息将在 Shopify 安全结算页填写。最终折扣、运费、税费和总额以该页面为准。' : 'Enter your address and payment details on Shopify’s secure checkout. Final discounts, shipping, tax and total are confirmed there.'}</p>
          <button className="lp-pill lp-pill-lime shop-place" type="submit">
            {locale === 'zh' ? '继续到 Shopify 结算' : 'Continue to Shopify checkout'}
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

        </aside>
      </div>
    </div>
  );
}
