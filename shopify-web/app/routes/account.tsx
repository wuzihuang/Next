import {Outlet, redirect} from 'react-router';
import type {Route} from './+types/account';
import {readAccount} from '~/lib/localShop.server';

export function shouldRevalidate() {
  return true;
}

export async function loader({request, context}: Route.LoaderArgs) {
  if (!readAccount(context.session)) {
    const next = new URL(request.url).pathname;
    return redirect(`/account/login?next=${encodeURIComponent(next)}`);
  }
  return null;
}

export default function AccountLayout() {
  return <Outlet />;
}
