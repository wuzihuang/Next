import {useLoaderData} from 'react-router';
import type {Route} from './+types/blogs._index';
import {JournalIndexView} from '~/components/shop/SiteViews';
import {localeFromRequest} from '~/lib/locale';
import {readLocale} from '~/lib/localShop.server';

export const meta: Route.MetaFunction = ({data}) => {
  return [{title: data?.locale === 'zh' ? 'NEXTBODY · 手记' : 'NEXTBODY · Journal'}];
};

export async function loader({request, context}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  return {locale};
}

export default function BlogsIndex() {
  const {locale} = useLoaderData<typeof loader>();
  return <JournalIndexView locale={locale} />;
}
