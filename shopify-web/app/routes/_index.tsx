import {data} from 'react-router';
import type {Route} from './+types/_index';
import {LandingPage} from '~/components/landing/LandingPage';
import {shopHeaders, writeLocale} from '~/lib/localShop.server';

export async function loader({context}: Route.LoaderArgs) {
  writeLocale(context.session, 'en');
  return data(null, {headers: await shopHeaders(context.session)});
}

export const meta: Route.MetaFunction = () => {
  return [
    {title: 'NEXTBODY · HOOP — The screenless band'},
    {
      name: 'description',
      content:
        'A band with no screen. It reads your heart, sleep, and training all day, and says it plainly in the NextBody app. $99 once for the band. App AI is NextBody Pro.',
    },
  ];
};

export default function Homepage() {
  return <LandingPage locale="en" />;
}
