import {Form, Link, NavLink, useLocation} from 'react-router';
import {useAside} from '~/components/Aside';
import type {ShopLocale} from '~/lib/locale';
import {localeHome} from '~/lib/locale';
import {shopCopy} from '~/lib/shopCopy';

export function Header({
  locale,
  cartCount,
  isLoggedIn,
}: {
  locale: ShopLocale;
  cartCount: number;
  isLoggedIn: boolean;
}) {
  const t = shopCopy(locale);
  const home = localeHome(locale);
  const {open} = useAside();

  return (
    <header className="lp-nav shop-nav">
      <Link className="lp-wordmark" prefetch="intent" to={home}>
        <span className="lp-wordmark-name">NEXTBODY</span>
        <span className="lp-pip" aria-hidden="true" />
      </Link>
      <nav className="lp-nav-mid" aria-label="Primary">
        <Link className="lp-nav-link" prefetch="intent" to={`${home}#band`}>
          {t.nav.band}
        </Link>
        <NavLink className="lp-nav-link" prefetch="intent" to="/collections/all">
          {t.nav.shop}
        </NavLink>
        <NavLink className="lp-nav-link" prefetch="intent" to="/pages/science">
          {t.nav.science}
        </NavLink>
      </nav>
      <div className="lp-nav-end">
        <button className="shop-menu-btn" onClick={() => open('mobile')} type="button">
          {t.nav.menu}
        </button>
        <div className="lp-langs">
          <LocaleSwitch locale={locale} />
        </div>
        <NavLink className="lp-sign" prefetch="intent" to={isLoggedIn ? '/account' : '/account/login'}>
          {isLoggedIn ? t.nav.account : t.nav.signIn}
        </NavLink>
        <button className="shop-search-btn" onClick={() => open('search')} type="button">
          {t.nav.search}
        </button>
        <button className="shop-cart-link" onClick={() => open('cart')} type="button">
          {t.nav.cart}
          <b>{cartCount}</b>
        </button>
        <Link className="lp-pill" prefetch="intent" to="/products/hoop">
          {t.nav.getHoop}
        </Link>
      </div>
    </header>
  );
}

export function HeaderMenu({locale}: {locale: ShopLocale}) {
  const t = shopCopy(locale);
  const home = localeHome(locale);
  const {close} = useAside();
  return (
    <nav className="header-menu-mobile" aria-label="Primary">
      <Link onClick={close} prefetch="intent" to={`${home}#band`}>
        {t.nav.band}
      </Link>
      <Link onClick={close} prefetch="intent" to="/collections/all">
        {t.nav.shop}
      </Link>
      <Link onClick={close} prefetch="intent" to="/pages/science">
        {t.nav.science}
      </Link>
      <Link onClick={close} prefetch="intent" to="/account">
        {t.nav.account}
      </Link>
      <Link onClick={close} prefetch="intent" to="/search">
        {t.nav.search}
      </Link>
      <Link onClick={close} prefetch="intent" to="/cart">
        {t.nav.cart}
      </Link>
      <Link onClick={close} prefetch="intent" to="/products/hoop">
        {t.nav.getHoop}
      </Link>
    </nav>
  );
}

function LocaleSwitch({locale}: {locale: ShopLocale}) {
  const location = useLocation();
  const redirectTo = `${location.pathname}${location.search}`;
  return (
    <>
      {locale === 'en' ? (
        <span className="lp-lang is-on">EN</span>
      ) : (
        <Form action="/locale">
          <input name="lang" type="hidden" value="en" />
          <input name="redirectTo" type="hidden" value={redirectTo} />
          <button className="lp-lang" type="submit">
            EN
          </button>
        </Form>
      )}
      <span className="lp-lang-rule" />
      {locale === 'zh' ? (
        <span className="lp-lang is-on">中文</span>
      ) : (
        <Form action="/locale">
          <input name="lang" type="hidden" value="zh" />
          <input name="redirectTo" type="hidden" value={redirectTo} />
          <button className="lp-lang" type="submit">
            中文
          </button>
        </Form>
      )}
    </>
  );
}
