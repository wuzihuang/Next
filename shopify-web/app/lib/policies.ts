import type {ShopLocale} from './locale';

export type PolicyHandle =
  | 'privacy-policy'
  | 'refund-policy'
  | 'shipping-policy'
  | 'terms-of-service';

export type PolicyPage = {
  handle: PolicyHandle;
  title: {en: string; zh: string};
  updated: string;
  sections: Array<{heading: {en: string; zh: string}; body: {en: string[]; zh: string[]}}>;
};

export const POLICIES: PolicyPage[] = [
  {
    handle: 'privacy-policy',
    title: {en: 'Privacy Policy', zh: '隐私政策'},
    updated: '2026-09-01',
    sections: [
      {
        heading: {en: 'Who we are', zh: '我们是谁'},
        body: {
          en: [
            'NextBody operates the HOOP band, the NextBody app, and this shop at nextbody.ai. This policy covers the website, the test checkout on this storefront, and the account you can open here.',
            'The NextBody app also reads wrist data from HOOP. App health data is described in the in-app privacy screen. This page is for the shop.',
          ],
          zh: [
            'NextBody 运营 HOOP 手环、NextBody App，以及 nextbody.ai 上的商店。本政策覆盖网站、本店的测试结算，以及你在这里创建的账户。',
            'App 还会从 HOOP 读取手腕数据。健康数据见 App 内的隐私页。本页只讲商店。',
          ],
        },
      },
      {
        heading: {en: 'What we collect on the shop', zh: '商店会收集什么'},
        body: {
          en: [
            'When you place a test order we store the name, email, shipping address, and the last four digits of the test card you typed. The full card number is not stored and is not sent to a payment processor.',
            'The cart and test orders live in a signed browser session cookie on this device. We do not sell this information.',
            'If you write to support, we keep the email and the message long enough to answer it.',
          ],
          zh: [
            '你提交测试订单时，我们会保存姓名、邮箱、收货地址，以及你输入的测试卡号后四位。完整卡号不会保存，也不会发给支付机构。',
            '购物车和测试订单存在这个设备上的签名会话 cookie 里。我们不会出售这些信息。',
            '如果你写信给支持，我们会把邮箱和信件保留到足够回复为止。',
          ],
        },
      },
      {
        heading: {en: 'Cookies', zh: 'Cookie'},
        body: {
          en: [
            'The shop uses a session cookie to keep your cart, language, test account, and test orders. It is httpOnly and stays on this site.',
            'We do not run advertising pixels on this storefront.',
          ],
          zh: [
            '商店用会话 cookie 保存购物车、语言、测试账户和测试订单。它是 httpOnly 的，只属于本站。',
            '本店不投放广告像素。',
          ],
        },
      },
      {
        heading: {en: 'Your choices', zh: '你的选择'},
        body: {
          en: [
            'Sign out to clear the test account from this browser. Clearing site data clears the cart and test orders.',
            'To ask for a copy or a deletion of shop records tied to your email, write to privacy@nextbody.ai.',
          ],
          zh: [
            '退出登录会清掉这个浏览器里的测试账户。清除站点数据会清掉购物车和测试订单。',
            '若要索取或删除与你邮箱相关的商店记录，请写信到 privacy@nextbody.ai。',
          ],
        },
      },
    ],
  },
  {
    handle: 'refund-policy',
    title: {en: 'Refund Policy', zh: '退款政策'},
    updated: '2026-09-01',
    sections: [
      {
        heading: {en: 'The live product', zh: '正式产品'},
        body: {
          en: [
            'When HOOP ships for real, you have 30 days from delivery to return an unused band in the original packing for a full refund of the product price. Return shipping is on us if the unit is defective.',
            'Opened straps can be returned unused. Worn straps are not refundable unless they are defective.',
          ],
          zh: [
            'HOOP 正式发货后，自签收起 30 天内，未使用且原包装完好的手环可全额退产品款。若设备本身有缺陷，退货运费由我们承担。',
            '未使用的表带可以退。已经戴过的表带，除非有缺陷，否则不退。',
          ],
        },
      },
      {
        heading: {en: 'This test shop', zh: '本测试店'},
        body: {
          en: [
            'Orders placed on this storefront are test orders. No payment is taken, so there is nothing to refund. The confirmation page is the end of the path.',
          ],
          zh: [
            '本店订单都是测试订单。没有扣款，因此也没有可退的钱。确认页就是这条路径的终点。',
          ],
        },
      },
    ],
  },
  {
    handle: 'shipping-policy',
    title: {en: 'Shipping Policy', zh: '配送政策'},
    updated: '2026-09-01',
    sections: [
      {
        heading: {en: 'Where we send HOOP', zh: '送到哪里'},
        body: {
          en: [
            'The live shop ships to the United States, Canada, the United Kingdom, the EU, Australia, Japan, Singapore, Hong Kong, Taiwan, and mainland China. Other destinations will open as customs paperwork is ready.',
            'On this test shop you can enter any of those countries. Nothing is fulfilled.',
          ],
          zh: [
            '正式商店发往美国、加拿大、英国、欧盟、澳大利亚、日本、新加坡、中国香港、中国台湾和中国大陆。其他地区会在清关文件齐了之后开放。',
            '本测试店可以填写上述国家或地区。不会真实发货。',
          ],
        },
      },
      {
        heading: {en: 'Cost and time', zh: '费用和时效'},
        body: {
          en: [
            'Shipping is $8 on strap-only carts. Carts of $99 or more — including a single HOOP — ship free.',
            'When we fulfill for real, most orders leave in 2–4 business days and arrive in 5–10. You get a tracking number by email.',
          ],
          zh: [
            '只买表带时运费 $8。满 $99（包括单独买一条 HOOP）免运费。',
            '正式履约后，多数订单 2–4 个工作日发出，5–10 个工作日到达。邮箱会收到运单号。',
          ],
        },
      },
    ],
  },
  {
    handle: 'terms-of-service',
    title: {en: 'Terms of Service', zh: '服务条款'},
    updated: '2026-09-01',
    sections: [
      {
        heading: {en: 'The shop', zh: '商店'},
        body: {
          en: [
            'These terms cover nextbody.ai and this Hydrogen storefront. By using the shop you agree to them.',
            'HOOP is for people 18 and over. It is not a medical device. It does not take an ECG and it does not diagnose, treat, or prevent any disease.',
          ],
          zh: [
            '本条款覆盖 nextbody.ai 和这个 Hydrogen 店面。使用商店即表示同意。',
            'HOOP 面向 18 岁及以上人群。它不是医疗器械。不做心电图，也不诊断、治疗或预防任何疾病。',
          ],
        },
      },
      {
        heading: {en: 'Price and subscription', zh: '价格和订阅'},
        body: {
          en: [
            'HOOP is $99 once. There is no membership and no monthly fee for the core app that reads the band.',
            'Prices on this test shop match the public price. They are not an offer to sell until a real checkout is turned on.',
          ],
          zh: [
            'HOOP 售价 $99，一次付清。读取手环的核心 App 没有会员费，也没有月费。',
            '本测试店的价格与公开售价一致。在正式结算打开之前，这不构成销售要约。',
          ],
        },
      },
      {
        heading: {en: 'Test checkout', zh: '测试结算'},
        body: {
          en: [
            'The checkout on this storefront is a closed test. It accepts a card number so you can walk the path. It does not charge the card and it does not create a real shipment.',
          ],
          zh: [
            '本店结算是闭环测试。它接受卡号，只为让你把路径走完。不会扣款，也不会产生真实发货。',
          ],
        },
      },
    ],
  },
];

export function getPolicy(handle: string): PolicyPage | undefined {
  return POLICIES.find((policy) => policy.handle === handle);
}

export function policyTitle(policy: PolicyPage, locale: ShopLocale): string {
  return locale === 'zh' ? policy.title.zh : policy.title.en;
}
