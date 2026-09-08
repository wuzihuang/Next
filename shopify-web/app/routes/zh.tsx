import {data} from 'react-router';
import type {Route} from './+types/zh';
import {LandingPage} from '~/components/landing/LandingPage';
import {shopHeaders, writeLocale} from '~/lib/localShop.server';

export async function loader({context}: Route.LoaderArgs) {
  writeLocale(context.session, 'zh');
  return data(null, {headers: await shopHeaders(context.session)});
}

export const meta: Route.MetaFunction = () => {
  return [
    {title: 'NEXTBODY · HOOP — 无屏手环'},
    {
      name: 'description',
      content:
        '一条没有屏幕的手环。它整天读你的心率、睡眠和训练，然后在 NextBody App 里把话说清楚。$99，永不订阅。',
    },
  ];
};

export default function ZhHomepage() {
  return <LandingPage locale="zh" />;
}
