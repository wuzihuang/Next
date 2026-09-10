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
        heading: {en: 'How the wrist reads', zh: '手腕怎么读'},
        body: {
          en: [
            'Green light for pulse, infrared and red for oxygen at night, a skin thermometer against the wrist, and a motion sensor that tells a step from a shrug. Nothing is inferred from a phone in a pocket.',
            'The band samples all day and holds the readings until the phone comes near. Bluetooth carries them across; the numbers do not go through anyone else on the way.',
          ],
          zh: [
            '绿光测脉搏，红光与红外在夜里测血氧，一枚贴着手腕的皮温传感器，以及一颗能把走一步和耸一下肩分开的运动传感器。没有一样是靠口袋里的手机猜出来的。',
            '手环整天采样，先存住，等手机靠近再交出去。蓝牙负责搬运；这一路上没有第三方碰到这些数字。',
          ],
        },
      },
      {
        heading: {en: 'What the numbers are for', zh: '这些数字用来做什么'},
        body: {
          en: [
            'Body battery is a budget: what the night put in, what the day has taken out. Training load is what you already spent. Sleep is the night scored on its own terms, not against a stranger.',
            'Each of them is compared to your own baseline. Two weeks of wear is what it takes before the app stops hedging and starts saying things plainly.',
          ],
          zh: [
            '身体电量是一本预算：夜里存进多少，白天花掉多少。训练负荷是你已经花掉的部分。睡眠按它自己的标准打分，不拿陌生人来比。',
            '每一项都只跟你自己的基线比。戴满两周，App 才会停止打太极，开始把话说直。',
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
      en: 'The short answers — the band, the app, the money, and this test shop. If yours is not here, write to shop@nextbody.ai.',
      zh: '短答案 —— 手环、App、钱，以及这家测试店。没有你要问的，就写 shop@nextbody.ai。',
    },
    image: '/landing/sensor.png',
    sections: [
      {
        heading: {en: 'How much is HOOP?', zh: 'HOOP 多少钱？'},
        body: {
          en: [
            '$99 once. Black or white. The knit nylon strap and the sport strap are both in the box, along with the charger.',
            'There is no subscription for the app that reads the band. Memberships in this category start at $239 a year; we decided not to be a club.',
          ],
          zh: [
            '$99 一次付清。黑色或白色。编织尼龙表带和运动表带都在盒里，充电器也在。',
            '读取手环的 App 没有订阅费。同类产品的会员费一年从 $239 起；我们决定不做会所。',
          ],
        },
      },
      {
        heading: {en: 'Does it have a screen?', zh: '有屏幕吗？'},
        body: {
          en: [
            'No. The wrist stays quiet — no glass, no glow, nothing to check in a meeting.',
            'You read the day in NextBody: on the phone, on the lock screen, on the widget. The face you see there is generated for that day, not picked from a list.',
          ],
          zh: [
            '没有。手腕保持安静 —— 没有玻璃，没有发光，开会时没有东西要瞄。',
            '你在 NextBody 里读这一天：手机上、锁屏上、小组件上。你看到的那张面孔是为那一天生成的，不是从列表里挑的。',
          ],
        },
      },
      {
        heading: {en: 'How long does the battery last?', zh: '续航多久？'},
        body: {
          en: [
            'About 5 days of ordinary wear, including sleep tracking every night. Heavy workout tracking pulls it down to 3 or 4.',
            'A full charge takes about 90 minutes on the magnetic puck. The app tells you the band is low before the band is low.',
          ],
          zh: [
            '正常佩戴约 5 天，包含每晚睡眠监测。大量训练记录会降到 3 到 4 天。',
            '磁吸充电座充满约 90 分钟。手环快没电之前，App 会先提醒你。',
          ],
        },
      },
      {
        heading: {en: 'Can I swim with it?', zh: '可以游泳吗？'},
        body: {
          en: [
            'Yes. Swim in it, shower in it, keep it on. It is rated 5 ATM, which covers pools, showers and open water.',
            'It is not for scuba or high-speed water sports. Rinse the sport strap with fresh water after the sea.',
          ],
          zh: [
            '可以。游泳戴，洗澡戴，一直戴着。防水等级 5 ATM，泳池、淋浴、开放水域都覆盖。',
            '不适合潜水和高速水上运动。下过海之后用清水冲一冲运动表带。',
          ],
        },
      },
      {
        heading: {en: 'Will it fit my wrist?', zh: '我的手腕戴得上吗？'},
        body: {
          en: [
            'One size, two straps. The knit nylon is elastic and fits roughly 135–210 mm; the sport strap is a pin buckle over the same range.',
            'Wear it a finger-width above the wrist bone, snug enough that it does not slide when you shake your arm. Optical readings live or die on that.',
          ],
          zh: [
            '单一尺寸，两条表带。编织尼龙有弹性，大致适配 135–210 mm；运动表带是同一区间的针扣。',
            '戴在腕骨上方一指宽处，紧到甩手臂时不会滑动。光学读数的成败全在这一点上。',
          ],
        },
      },
      {
        heading: {en: 'iPhone or Android?', zh: 'iPhone 还是安卓？'},
        body: {
          en: [
            'The NextBody app ships on iPhone first, iOS 17 and later. The Android build follows.',
            'The band stores its readings on its own, so a day without the phone is not a lost day.',
          ],
          zh: [
            'NextBody App 先上 iPhone，iOS 17 及以上。安卓版随后。',
            '手环自己会存读数，所以有一天没带手机，那一天也不会丢。',
          ],
        },
      },
      {
        heading: {en: 'How accurate is it?', zh: '准不准？'},
        body: {
          en: [
            'Good enough to run your week, not good enough to run a clinic. Resting heart rate, sleep timing and step count are solid. Continuous heart rate during heavy lifting is the hardest case for any optical sensor, including this one.',
            'Body composition is an estimate from impedance and your own history. Weigh and scan at the same time of day and read the trend, not the decimal.',
          ],
          zh: [
            '足以管好你的一周，不足以支撑一间诊所。静息心率、入睡时间和步数很稳。大重量训练时的连续心率是所有光学传感器最难的场景，这一颗也一样。',
            '身体成分是由阻抗和你自己的历史推出的估计值。固定时间称重和扫描，看趋势，不要盯小数点。',
          ],
        },
      },
      {
        heading: {en: 'What does the coach actually see?', zh: 'AI 教练到底看到什么？'},
        body: {
          en: [
            'Your night, your HRV, your training load, your meals and your battery — the same numbers you can open yourself. It says what it read before it says what it thinks.',
            'It is a model. It can be confidently wrong. It is not a doctor and it does not pretend to be one.',
          ],
          zh: [
            '你的夜晚、你的 HRV、你的训练负荷、你的饮食和你的电量 —— 就是你自己能打开的那些数字。它先说读到了什么，再说它怎么想。',
            '它是模型，可能非常笃定地说错。它不是医生，也不假装是。',
          ],
        },
      },
      {
        heading: {en: 'Who owns my data?', zh: '数据归谁？'},
        body: {
          en: [
            'You do. Export it whenever you want, delete it whenever you want, and closing the account deletes the lot within 30 days.',
            'It is never sold and never used for advertising. The Privacy Policy says exactly who touches it and for how long.',
          ],
          zh: [
            '归你。随时导出，随时删除；注销账户会在 30 天内删光。',
            '永不出售，永不用于广告。《隐私政策》里写明了谁会碰到它、碰多久。',
          ],
        },
      },
      {
        heading: {en: 'Does it track my location?', zh: '它会记录我的位置吗？'},
        body: {
          en: [
            'The band has no GPS of its own. If a workout needs a route, it comes from the phone, and only while that workout is running.',
            'There is no microphone and no camera on the band.',
          ],
          zh: [
            '手环没有自己的 GPS。若某次训练需要轨迹，轨迹来自手机，而且只在那次训练进行时。',
            '手环上没有麦克风，也没有摄像头。',
          ],
        },
      },
      {
        heading: {en: 'What is the warranty?', zh: '保修多久？'},
        body: {
          en: [
            'Twelve months on the band against manufacturing defects, six on the straps, counted from delivery. A defect gets a repair, a replacement, or your money back.',
            'You also have 30 days from delivery to send an unused band back for any reason at all.',
          ],
          zh: [
            '手环制造缺陷保修 12 个月，表带 6 个月，自签收起算。出现缺陷可维修、更换或退款。',
            '另外，自签收起 30 天内，未使用的手环可以无理由退回。',
          ],
        },
      },
      {
        heading: {en: 'When does it ship?', zh: '什么时候发货？'},
        body: {
          en: [
            'Live orders leave in 2 to 4 business days and land in 3 to 5 inside the United States, 5 to 10 elsewhere. Straps ship for $8; a cart of $99 or more ships free.',
          ],
          zh: [
            '正式订单 2 到 4 个工作日出库，美国境内 3 到 5 天送达，其他地区 5 到 10 天。表带运费 $8；满 $99 免运费。',
          ],
        },
      },
      {
        heading: {en: 'Is this checkout real?', zh: '这里的结算是真的吗？'},
        body: {
          en: [
            'No. This storefront closes the path with a test card so you can add to cart, pay, and see an order. You will not be charged, and nothing ships.',
            'When the live checkout opens, the prices on these pages are the prices.',
          ],
          zh: [
            '不是。本店用测试卡把路径走完，让你能加购、付款并看到订单。不会扣款，也不会发货。',
            '正式结算打开时，这些页面上的价格就是价格。',
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
        heading: {en: 'What we make', zh: '我们做什么'},
        body: {
          en: [
            'HOOP is a steel band with no display. It reads twelve signals on the wrist all day and all night and hands them to the NextBody app, which turns them into three numbers that run the day: what you have left, what you already spent, and what the day still wants to eat.',
            'Everything else — the instruments, the night, the plan, the coach — sits one layer down, there when you want the why.',
          ],
          zh: [
            'HOOP 是一条没有显示屏的钢制手环。它整日整夜在手腕上读十二种数据，交给 NextBody App，由 App 变成管住一天的三个数：你还剩多少、已经花了多少、今天还该吃多少。',
            '其余的一切 —— 仪表、夜晚、计划、教练 —— 都在下一层，你想知道为什么时它就在。',
          ],
        },
      },
      {
        heading: {en: 'Why no screen', zh: '为什么不要屏幕'},
        body: {
          en: [
            'A watch asks you to look. Two hundred times a day, for a number that has not moved. That is the part of wearables nobody enjoys and everybody accepts.',
            'Taking the glass off the arm bought us three things: five days on a charge, a case thin enough to sleep in, and a wrist that does not interrupt you. The reading waits in the app, where there is room to say a whole sentence instead of a digit.',
          ],
          zh: [
            '表要求你看。一天两百次，看一个根本没动的数字。这是可穿戴里没人享受、人人接受的那部分。',
            '把玻璃从手臂上拿掉，换来三件事：五天续航、薄到能戴着睡的机身，以及一只不打断你的手腕。读数在 App 里等你，那里有地方说完整一句话，而不是只显示一个数字。',
          ],
        },
      },
      {
        heading: {en: 'Why $99', zh: '为什么是 $99'},
        body: {
          en: [
            'Memberships in this category start at $239 a year. Pay for two years and you have bought the hardware three times over — and if you stop paying, your own nights stop being readable.',
            'HOOP is $99 once so the band is not a club. Your data is not a hostage, and the core reading has no meter on it.',
            'The next version of you is already under the skin. HOOP just makes it visible.',
          ],
          zh: [
            '同类产品的会员费一年从 $239 起。付两年，等于把硬件买了三遍 —— 而一旦停付，连你自己的夜晚都读不了了。',
            'HOOP 只要 $99，一次付清，手环不是会所。你的数据不是人质，核心读数上没有计价器。',
            '下一个版本的你，已经在皮肤底下了。HOOP 只是让它被看见。',
          ],
        },
      },
      {
        heading: {en: 'How we work', zh: '我们怎么做事'},
        body: {
          en: [
            'Small team, one product, no roadmap written for a stage. We wear the thing every day, and the day a number lies to us we fix the number before we ship anything new.',
            'We do not run ads on your body. We do not sell readings. When we do not know something — and an optical sensor on a wrist leaves plenty unknown — the app says so instead of inventing a score.',
          ],
          zh: [
            '小团队，一个产品，没有为发布会写的路线图。我们自己每天戴着；哪天某个数字对我们说了谎，我们先修那个数字，再谈新功能。',
            '我们不在你的身体上投广告，不出售读数。遇到我们不知道的事 —— 手腕上的光学传感器留下的未知不少 —— App 会直说，而不是编一个分数出来。',
          ],
        },
      },
      {
        heading: {en: 'What it is not', zh: '它不是什么'},
        body: {
          en: [
            'Not a medical device, not a diagnosis, not a doctor. No ECG, no blood pressure, no promise about a condition. For people 18 and over.',
            'It is an instrument for managing a body you already live in.',
          ],
          zh: [
            '不是医疗器械，不是诊断，不是医生。不做心电图，不测血压，不对任何病症做承诺。面向 18 岁及以上人群。',
            '它是一件仪器，用来管理你已经住在里面的那副身体。',
          ],
        },
      },
      {
        heading: {en: 'Where this shop stands', zh: '这家店现在的状态'},
        body: {
          en: [
            'This storefront is a working test: real pages, real cart, real order path, a closed test checkout at the end. Nothing is charged and nothing ships yet.',
            'Write to shop@nextbody.ai if you want to know when it opens for real.',
          ],
          zh: [
            '这个店面是一次可运行的测试：真实的页面、真实的购物车、真实的下单路径，末端是闭环测试结算。不扣款，暂不发货。',
            '想知道什么时候正式开卖，写 shop@nextbody.ai。',
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
      en: 'Four addresses and a person behind each one. We read what you send.',
      zh: '四个邮箱，每个后面都有一个人。我们会读你寄来的信。',
    },
    image: '/landing/hero.png',
    sections: [
      {
        heading: {en: 'Shop and orders', zh: '商店与订单'},
        body: {
          en: [
            'shop@nextbody.ai — orders, returns, warranty, shipping, and anything about the band itself.',
            'Put the order number in the subject line if you have one. We answer within one business day, Monday to Friday.',
          ],
          zh: [
            'shop@nextbody.ai —— 订单、退货、保修、配送，以及关于手环本身的一切。',
            '有订单号就写在主题里。周一至周五，一个工作日内回复。',
          ],
        },
      },
      {
        heading: {en: 'Privacy and your data', zh: '隐私与你的数据'},
        body: {
          en: [
            'privacy@nextbody.ai — a copy of your data, a correction, a deletion, or a question about the Privacy Policy.',
            'Write from the address on the account so we know it is you. We answer within 30 days and usually much sooner, and we never charge for it.',
          ],
          zh: [
            'privacy@nextbody.ai —— 索取数据副本、更正、删除，或关于《隐私政策》的任何问题。',
            '请用账户上的邮箱写信，我们才能确认是你。30 天内答复，通常快得多，且从不收费。',
          ],
        },
      },
      {
        heading: {en: 'Press', zh: '媒体'},
        body: {
          en: [
            'press@nextbody.ai — product photography, specs, review units, and interviews.',
            'Say your outlet and your deadline in the first line and we will match it if we can.',
          ],
          zh: [
            'press@nextbody.ai —— 产品图、参数、评测机与采访。',
            '第一行写清媒体名和截稿时间，能配合的我们都会配合。',
          ],
        },
      },
      {
        heading: {en: 'Security', zh: '安全'},
        body: {
          en: [
            'security@nextbody.ai — if you have found a hole, tell us before you tell anyone else and give us a way to reach you.',
            'We will not send lawyers after good-faith research.',
          ],
          zh: [
            'security@nextbody.ai —— 若你发现了漏洞，请先告诉我们，再告诉别人，并留下能联系到你的方式。',
            '我们不会对善意研究发律师函。',
          ],
        },
      },
      {
        heading: {en: 'A few honest notes', zh: '几句实话'},
        body: {
          en: [
            'There is no phone line yet, and this test shop does not open a ticket from a form. Email is the whole support system, and it is read by the people who build the thing.',
            'Returns go to the address we send you with a return number — please do not post anything back before you have one.',
          ],
          zh: [
            '目前没有电话，本测试店也不会从表单生成工单。邮件就是全部的支持系统，而读信的人就是做这东西的人。',
            '退货请寄到我们随退货编号一起给你的地址 —— 拿到编号之前请不要寄出。',
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
