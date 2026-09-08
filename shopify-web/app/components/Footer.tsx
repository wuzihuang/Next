import {Link} from 'react-router';
import type {ShopLocale} from '~/lib/locale';
import {localeHome} from '~/lib/locale';
import {shopCopy} from '~/lib/shopCopy';

export function Footer({locale}: {locale: ShopLocale}) {
  const t = shopCopy(locale);
  const home = localeHome(locale);
  return (
    <div className="shop-foot-wrap">
    <footer className="lp-foot shop-foot">
      <div className="lp-foot-brand">
        <p className="lp-wordmark">
          <span className="lp-wordmark-name">NEXTBODY</span>
          <span className="lp-pip" />
        </p>
        <p>{t.footer.tag}</p>
      </div>
      <div className="lp-foot-cols">
        <nav className="lp-foot-col" aria-label={t.footer.product}>
          <b>{t.footer.product}</b>
          <Link prefetch="intent" to={`${home}#band`}>
            {t.footer.band}
          </Link>
          <Link prefetch="intent" to="/collections/all">
            {t.footer.shop}
          </Link>
          <Link prefetch="intent" to="/pages/science">
            {t.footer.science}
          </Link>
          <Link prefetch="intent" to="/blogs">
            {t.footer.journal}
          </Link>
        </nav>
        <nav className="lp-foot-col" aria-label={t.footer.support}>
          <b>{t.footer.support}</b>
          <Link prefetch="intent" to="/pages/faq">
            {t.footer.faq}
          </Link>
          <Link prefetch="intent" to="/pages/about">
            {t.footer.about}
          </Link>
          <Link prefetch="intent" to="/pages/contact">
            {t.footer.contact}
          </Link>
        </nav>
        <nav className="lp-foot-col" aria-label={t.footer.legal}>
          <b>{t.footer.legal}</b>
          <Link prefetch="intent" to="/policies/privacy-policy">
            {t.footer.privacy}
          </Link>
          <Link prefetch="intent" to="/policies/refund-policy">
            {t.footer.refund}
          </Link>
          <Link prefetch="intent" to="/policies/shipping-policy">
            {t.footer.shipping}
          </Link>
          <Link prefetch="intent" to="/policies/terms-of-service">
            {t.footer.terms}
          </Link>
        </nav>
      </div>
    </footer>
    <div className="lp-legal">
      <span>{t.footer.disclaimer}</span>
      <span>{t.footer.copy}</span>
    </div>
    </div>
  );
}
