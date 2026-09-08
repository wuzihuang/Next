import type {ShopLocale} from './locale';

export type SitePage = {
  handle: string;
  title: {en: string; zh: string};
  kicker: {en: string; zh: string};
  lede: {en: string; zh: string};
  image?: string;
  sections: Array<{heading: {en: string; zh: string}; body: {en: string[]; zh: string[]}}>;
};

export type JournalArticle = {
  handle: string;
  title: {en: string; zh: string};
  lede: {en: string; zh: string};
  date: string;
  image: string;
  body: {en: string[]; zh: string[]};
};

export const SITE_PAGES: SitePage[] = [
  {
    handle: 'science',
    title: {en: 'Science', zh: '科学依据'},
    kicker: {en: 'WHAT IT READS', zh: '它读什么'},
    lede: {
      en: 'The wrist is the instrument. The app is the page. HOOP keeps twelve signals. It does not run other apps.',
      zh: '手腕是仪器。App 是纸面。HOOP 读十二种数据。它不跑别的 App。',
    },
    image: '/band/lifestyle-train.jpg',
    sections: [
      {
        heading: {en: 'Twelve signals', zh: '十二种数据'},
        body: {
          en: [
            'Body battery, training load, and sleep run the day. Heart, blood oxygen, stress, temperature, calories, steps, distance, and active energy sit on the instruments. Composition is a scan you start yourself.',
            'Night HRV lives on Sleep. There is no blood pressure. There is no ECG.',
          ],
          zh: [
            '身体电量、训练负荷和睡眠管住一天。心率、血氧、压力、温度、热量、步数、距离和活动能量在仪表上。身体成分是一次由你发起的扫描。',
            '夜间 HRV 归在睡眠里。不测血压。不做心电图。',
          ],
        },
      },
      {
        heading: {en: 'What it is not', zh: '它不是什么'},
        body: {
          en: [
            'HOOP is not a medical device. It does not diagnose. It is for people 18 and over.',
            'The numbers are for managing a body you already know — when to train, how much to eat, whether last night was enough.',
          ],
          zh: [
            'HOOP 不是医疗器械。它不做诊断。面向 18 岁及以上。',
            '这些数字是为了管你已经认识的那副身体 — 什么时候练、吃多少、昨晚够不够。',
          ],
        },
      },
    ],
  },
  {
    handle: 'faq',
    title: {en: 'FAQ', zh: '常见问题'},
    kicker: {en: 'ASKED', zh: '有人问过'},
    lede: {
      en: 'The short answers. The band, the price, the app, and this test shop.',
      zh: '短答案。手环、价格、App，以及这家测试店。',
    },
    image: '/landing/sensor.png',
    sections: [
      {
        heading: {en: 'How much is HOOP?', zh: 'HOOP 多少钱？'},
        body: {
          en: [
            '$99 once. Black or white. Knit nylon and the sport strap both come in the box. There is no subscription for the app that reads the band.',
          ],
          zh: ['$99 一次付清。黑色或白色。编织尼龙和运动表带都在盒里。读取手环的 App 没有订阅费。'],
        },
      },
      {
        heading: {en: 'Does it have a screen?', zh: '有屏幕吗？'},
        body: {
          en: [
            'No. The wrist stays quiet. You read the day in NextBody — on the phone, on the lock screen, on the widget.',
          ],
          zh: ['没有。手腕保持安静。你在 NextBody 里读这一天 — 手机上、锁屏上、小组件上。'],
        },
      },
      {
        heading: {en: 'Can I swim with it?', zh: '可以游泳吗？'},
        body: {
          en: ['Yes. Swim in it. Shower in it. Keep it on. The sport strap is built for wet work.'],
          zh: ['可以。游泳戴，洗澡戴，一直戴着。运动表带就是为会湿的日子做的。'],
        },
      },
      {
        heading: {en: 'Is this checkout real?', zh: '这里的结算是真的吗？'},
        body: {
          en: [
            'No. This storefront closes the path with a test card so you can add to cart, pay, and see an order. You will not be charged.',
          ],
          zh: [
            '不是。本店用测试卡把路径走完，让你能加购、付款并看到订单。不会扣款。',
          ],
        },
      },
    ],
  },
  {
    handle: 'about',
    title: {en: 'About', zh: '关于'},
    kicker: {en: 'NEXTBODY', zh: 'NEXTBODY'},
    lede: {
      en: 'A band with no screen, and an app that says the day plainly. Built so more people can actually manage a body.',
      zh: '一条没有屏幕的手环，和一个把一天说清楚的 App。为了让更多人真的管得起自己的身体。',
    },
    image: '/landing/chase.png',
    sections: [
      {
        heading: {en: 'Why $99', zh: '为什么是 $99'},
        body: {
          en: [
            'Memberships in this category start at $239 a year. HOOP is $99 once so the band is not a club.',
            'The next version of you is already under the skin. HOOP just makes it visible.',
          ],
          zh: [
            '同类产品的会员费一年从 $239 起。HOOP 只要 $99，一次付清，手环不是会所。',
            '下一个版本的你，已经在皮肤底下了。HOOP 只是让它被看见。',
          ],
        },
      },
    ],
  },
  {
    handle: 'contact',
    title: {en: 'Contact', zh: '联系'},
    kicker: {en: 'WRITE', zh: '写信'},
    lede: {
      en: 'Shop, press, and privacy. We read what you send.',
      zh: '商店、媒体和隐私。我们会读你寄来的信。',
    },
    image: '/landing/hero.png',
    sections: [
      {
        heading: {en: 'Addresses', zh: '邮箱'},
        body: {
          en: [
            'Shop and orders: shop@nextbody.ai',
            'Privacy: privacy@nextbody.ai',
            'Press: press@nextbody.ai',
            'This test shop does not open a ticket from the form. Write the email.',
          ],
          zh: [
            '商店与订单：shop@nextbody.ai',
            '隐私：privacy@nextbody.ai',
            '媒体：press@nextbody.ai',
            '本测试店没有表单工单。请直接写信。',
          ],
        },
      },
    ],
  },
];

export const JOURNAL: JournalArticle[] = [
  {
    handle: 'wrist-not-watch',
    title: {en: 'The wrist is not a watch', zh: '手腕不是一块表'},
    lede: {
      en: 'HOOP keeps the glass off the arm. The reading waits in the app.',
      zh: 'HOOP 不把玻璃戴在手臂上。读数在 App 里等你。',
    },
    date: '2026-08-12',
    image: '/landing/buckle.png',
    body: {
      en: [
        'A watch asks you to look. A band that has nothing to look at asks you to wear it.',
        'The twelve signals still get taken. They land on Home, on page two, on the plan — not on a face you glance at in a meeting.',
      ],
      zh: [
        '表要求你看。一条没什么可看的手环，只要求你戴着。',
        '十二种数据照样会读。它们落在首页、第二页和计划上 — 而不是你在会上扫一眼的表盘上。',
      ],
    },
  },
  {
    handle: 'three-numbers',
    title: {en: 'Three numbers that run the day', zh: '管住一天的三个数'},
    lede: {
      en: 'Battery. Load. Calories. The rest of the instruments wait on page two.',
      zh: '电量。负荷。热量。其余仪表在第二页。',
    },
    date: '2026-07-28',
    image: '/landing/phone-home.png',
    body: {
      en: [
        'Body battery says how much you have left. Training says how much you already spent. Calories say what the day still wants to eat.',
        'That is enough to move. The eight instruments are there when you want the why.',
      ],
      zh: [
        '身体电量说你还剩多少。训练说你已经花了多少。热量说今天还该吃到多少。',
        '这些就够你动起来。想知道为什么时，八个仪表在。',
      ],
    },
  },
  {
    handle: 'no-subscription',
    title: {en: 'No subscription. Ever.', zh: '永不订阅。'},
    lede: {
      en: 'The band is $99. The app that reads it does not rent you back your own night.',
      zh: '手环 $99。读取它的 App 不会把你自己的夜晚再租给你。',
    },
    date: '2026-06-04',
    image: '/landing/finishes.png',
    body: {
      en: [
        'Memberships in this category start at $239 a year. That is a second product.',
        'HOOP is the band and the reading. You buy it once.',
      ],
      zh: [
        '同类产品的会员费一年从 $239 起。那是另一件产品。',
        'HOOP 是手环和读数。你买一次。',
      ],
    },
  },
];

export function getSitePage(handle: string): SitePage | undefined {
  return SITE_PAGES.find((page) => page.handle === handle);
}

export function getArticle(handle: string): JournalArticle | undefined {
  return JOURNAL.find((article) => article.handle === handle);
}

export function pageTitle(
  page: {title: {en: string; zh: string}},
  locale: ShopLocale,
): string {
  return locale === 'zh' ? page.title.zh : page.title.en;
}
