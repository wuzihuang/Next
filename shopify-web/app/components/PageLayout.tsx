import {Form, Link, useLocation, useSearchParams} from 'react-router';
import {useEffect} from 'react';
import {Aside, useAside} from '~/components/Aside';
import {Footer} from '~/components/Footer';
import {Header, HeaderMenu} from '~/components/Header';
import {CartView} from '~/components/shop/CartView';
import type {ShopState} from '~/lib/localShop.server';
import type {ShopLocale} from '~/lib/locale';
import {shopCopy} from '~/lib/shopCopy';

export function PageLayout({
  children,
  shop,
}: {
  children?: React.ReactNode;
  shop: ShopState;
}) {
  const location = useLocation();
  const isLanding = location.pathname === '/' || location.pathname === '/zh';
  const locale = shop.locale;

  if (isLanding) {
    return (
      <Aside.Provider>
        {children}
      </Aside.Provider>
    );
  }

  return (
    <Aside.Provider>
      <div className="lp shop-app" data-locale={locale}>
        <CartAside locale={locale} shop={shop} />
        <SearchAside locale={locale} />
        <MobileMenuAside locale={locale} />
        <CartOpener />
        <Header
          cartCount={shop.totals.quantity}
          isLoggedIn={Boolean(shop.account)}
          locale={locale}
        />
        <main className="site-main">{children}</main>
        <Footer locale={locale} />
      </div>
    </Aside.Provider>
  );
}

function CartOpener() {
  const [params] = useSearchParams();
  const {open} = useAside();
  useEffect(() => {
    if (params.get('cart') === 'open') open('cart');
  }, [open, params]);
  return null;
}

function CartAside({locale, shop}: {locale: ShopLocale; shop: ShopState}) {
  const t = shopCopy(locale);
  return (
    <Aside heading={t.cart.title} type="cart">
      <CartView layout="aside" locale={locale} shop={shop} />
    </Aside>
  );
}

function SearchAside({locale}: {locale: ShopLocale}) {
  const t = shopCopy(locale);
  const {close} = useAside();
  return (
    <Aside heading={t.search.title} type="search">
      <Form action="/search" className="shop-search" onSubmit={close}>
        <input name="q" placeholder={t.search.placeholder} type="search" />
        <button className="lp-pill" type="submit">
          {t.search.submit}
        </button>
      </Form>
      <p>
        <Link onClick={close} prefetch="intent" to="/search">
          {t.search.title}
        </Link>
      </p>
    </Aside>
  );
}

function MobileMenuAside({locale}: {locale: ShopLocale}) {
  const t = shopCopy(locale);
  return (
    <Aside heading={t.nav.menu} type="mobile">
      <HeaderMenu locale={locale} />
    </Aside>
  );
}
