import {useLoaderData} from 'react-router';
import type {Route} from './+types/blogs.$blogHandle.$articleHandle';
import {JournalArticleView} from '~/components/shop/SiteViews';
import {localeFromRequest} from '~/lib/locale';
import {readLocale} from '~/lib/localShop.server';
import {getArticle, pageTitle} from '~/lib/sitePages';

export const meta: Route.MetaFunction = ({data}) => {
  if (!data) return [{title: 'NEXTBODY'}];
  return [{title: `NEXTBODY · ${pageTitle(data.article, data.locale)}`}];
};

export async function loader({request, context, params}: Route.LoaderArgs) {
  const locale = localeFromRequest(request, readLocale(context.session));
  if (params.blogHandle !== 'journal') throw new Response(null, {status: 404});
  const article = getArticle(params.articleHandle || '');
  if (!article) throw new Response(null, {status: 404});
  return {locale, article};
}

export default function JournalArticle() {
  const {locale, article} = useLoaderData<typeof loader>();
  return <JournalArticleView article={article} locale={locale} />;
}
