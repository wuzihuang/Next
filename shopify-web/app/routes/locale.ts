import {redirect} from 'react-router';
import type {Route} from './+types/locale';
import {shopHeaders, writeLocale} from '~/lib/localShop.server';

async function setLocale(request: Request, context: Route.LoaderArgs['context']) {
  let lang = 'en';
  let redirectTo = '/';
  if (request.method === 'POST') {
    const form = await request.formData();
    lang = String(form.get('lang') || 'en');
    redirectTo = String(form.get('redirectTo') || '/');
  } else {
    const url = new URL(request.url);
    lang = url.searchParams.get('lang') || 'en';
    redirectTo = url.searchParams.get('redirectTo') || '/';
  }
  writeLocale(context.session, lang === 'zh' ? 'zh' : 'en');
  const safe =
    redirectTo.startsWith('/') && !redirectTo.startsWith('//') ? redirectTo : '/';
  return redirect(safe, {headers: await shopHeaders(context.session)});
}

export async function loader({request, context}: Route.LoaderArgs) {
  return setLocale(request, context);
}

export async function action({request, context}: Route.ActionArgs) {
  return setLocale(request, context);
}
