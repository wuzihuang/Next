import {useRouteLoaderData} from 'react-router';
import type {RootLoader} from '~/root';
import {NotFoundView} from '~/components/shop/SiteViews';

export default function CatchAllPage() {
  const data = useRouteLoaderData<RootLoader>('root');
  return <NotFoundView locale={data?.localShop.locale ?? 'en'} />;
}
