import {Suspense} from 'react';
import {Await, NavLink, useAsyncValue} from 'react-router';
import {
  type CartViewPayload,
  useAnalytics,
  useOptimisticCart,
} from '@shopify/hydrogen';
import type {HeaderQuery, CartApiQueryFragment} from 'storefrontapi.generated';
import {useAside} from '~/components/Aside';

interface HeaderProps {
  header: HeaderQuery;
  cart: Promise<CartApiQueryFragment | null>;
  isLoggedIn: Promise<boolean>;
  publicStoreDomain: string;
}

type Viewport = 'desktop' | 'mobile';

const MARKETING_NAV = [
  {id: 'band', title: 'The Band', href: '/#band'},
  {id: 'shop', title: 'Shop', to: '/collections/all'},
  {id: 'science', title: 'Science', href: '/#science'},
] as const;

export function Header({
  isLoggedIn,
  cart,
}: HeaderProps) {
  return (
    <header className="header">
      <HeaderMenuMobileToggle />
      <NavLink className="wordmark" prefetch="intent" to="/" end>
        <span className="wordmark-name">NEXTBODY</span>
        <span className="wordmark-pip" aria-hidden="true" />
      </NavLink>
      <HeaderMenu viewport="desktop" />
      <HeaderCtas isLoggedIn={isLoggedIn} cart={cart} />
    </header>
  );
}

export function HeaderMenu({viewport}: {viewport: Viewport}) {
  const className = `header-menu-${viewport}`;
  const {close, open} = useAside();

  return (
    <nav className={className} role="navigation" aria-label="Primary">
      {MARKETING_NAV.map((item) =>
        'href' in item ? (
          <a className="header-link" href={item.href} key={item.id} onClick={close}>
            {item.title}
          </a>
        ) : (
          <NavLink
            className={({isActive, isPending}) => navClass(isActive, isPending)}
            end
            key={item.id}
            onClick={close}
            prefetch="intent"
            to={item.to}
          >
            {item.title}
          </NavLink>
        ),
      )}
      {viewport === 'mobile' ? (
        <>
          <NavLink
            className={({isActive, isPending}) => navClass(isActive, isPending)}
            onClick={close}
            prefetch="intent"
            to="/account"
          >
            Account
          </NavLink>
          <button
            className="reset header-link"
            onClick={() => {
              close();
              open('search');
            }}
            type="button"
          >
            Search
          </button>
        </>
      ) : null}
    </nav>
  );
}

function HeaderCtas({
  isLoggedIn,
  cart,
}: Pick<HeaderProps, 'isLoggedIn' | 'cart'>) {
  return (
    <nav className="header-ctas" role="navigation" aria-label="Account">
      <NavLink
        className={({isActive, isPending}) => navClass(isActive, isPending)}
        prefetch="intent"
        to="/account"
      >
        <Suspense fallback="Sign in">
          <Await resolve={isLoggedIn} errorElement="Sign in">
            {(loggedIn) => (loggedIn ? 'Account' : 'Sign in')}
          </Await>
        </Suspense>
      </NavLink>
      <SearchToggle />
      <CartToggle cart={cart} />
      <NavLink className="btn header-get" prefetch="intent" to="/collections/all">
        Get HOOP
      </NavLink>
    </nav>
  );
}

function HeaderMenuMobileToggle() {
  const {open} = useAside();
  return (
    <button
      className="header-menu-mobile-toggle reset"
      onClick={() => open('mobile')}
      type="button"
    >
      Menu
    </button>
  );
}

function SearchToggle() {
  const {open} = useAside();
  return (
    <button className="reset header-text-btn" onClick={() => open('search')} type="button">
      Search
    </button>
  );
}

function CartBadge({count}: {count: number}) {
  const {open} = useAside();
  const {publish, shop, cart, prevCart} = useAnalytics();

  return (
    <a
      className="header-cart"
      href="/cart"
      onClick={(event) => {
        event.preventDefault();
        open('cart');
        publish('cart_viewed', {
          cart,
          prevCart,
          shop,
          url: window.location.href || '',
        } as CartViewPayload);
      }}
    >
      Cart <span aria-label={`${count} items`}>{count}</span>
    </a>
  );
}

function CartToggle({cart}: Pick<HeaderProps, 'cart'>) {
  return (
    <Suspense fallback={<CartBadge count={0} />}>
      <Await resolve={cart}>
        <CartBanner />
      </Await>
    </Suspense>
  );
}

function CartBanner() {
  const originalCart = useAsyncValue() as CartApiQueryFragment | null;
  const cart = useOptimisticCart(originalCart);
  return <CartBadge count={cart?.totalQuantity ?? 0} />;
}

function navClass(isActive: boolean, isPending: boolean) {
  return [
    'header-link',
    isActive ? 'is-active' : '',
    isPending ? 'is-pending' : '',
  ]
    .filter(Boolean)
    .join(' ');
}
