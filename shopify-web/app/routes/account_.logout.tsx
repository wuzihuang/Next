import {redirect} from 'react-router';
import type {Route} from './+types/account_.logout';
import {shopHeaders, writeAccount} from '~/lib/localShop.server';

export async function loader() {
  return redirect('/');
}

export async function action({context}: Route.ActionArgs) {
  writeAccount(context.session, null);
  return redirect('/', {headers: await shopHeaders(context.session)});
}
