import {useLoaderData} from 'react-router';
import type {Route} from './+types/pages.$handle';
import {ContentPageView} from '~/components/shop/SiteViews';
import {localeFromRequest} from '~/lib/locale';
import {readLocale} from '~/lib/localShop.server';
import {getSitePage, pageTitle} from '~/lib/sitePages';

export const meta: Route.MetaFunction = ({data}) => {
  if (!data) return [{title: 'NEXTBODY'}];
  return [{title: `NEXTBODY · ${pageTitle(data.page, data.locale)}`}];
};

export async function loader({request, context, params}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  const page = getSitePage(params.handle || '');
  if (!page) throw new Response(null, {status: 404});
  return {locale, page};
}

export default function SitePageHandle() {
  const {locale, page} = useLoaderData<typeof loader>();
  return <ContentPageView locale={locale} page={page} />;
}
