export type LandingLocale = 'en' | 'zh';

export type LandingCopy = {
  htmlLang: string;
  title: string;
  description: string;
  nav: {
    band: string;
    app: string;
    science: string;
    signIn: string;
    getHoop: string;
  };
  hero: {
    kicker: string;
    title: string[];
    lede: string;
    cta: string;
    noSub: string;
    floor: string[];
  };
  gallery: {
    kicker: string;
    title: string[];
    lede: string;
    note: string;
    sensorLabel: string;
    sensorRatio: string;
  };
  highlights: {
    kicker: string;
    title: string;
    cards: Array<{kicker: string; title: string}>;
    triad: Array<{value: string; label: string}>;
    scan: {fat: string; fatUnit: string; fatLabel: string; bmi: string; bmiLabel: string};
    coach: {question: string; kicker: string; answer: string; action: string};
    aiDisplay: {
      question: string;
      nights: string;
      caption: string;
    };
  };
  appRead: {
    title: string;
    lede: string;
    note: string;
    cta: string;
  };
  radar: {
    kicker: string;
    title: string[];
    lede: string;
  };
  composition: {
    kicker: string;
    title: string;
    lede: string;
    phoneTitle: string;
    phoneLede: string;
    phoneCta: string;
    phoneHint: string;
  };
  stress: {
    title: string;
    lede: string;
    live: string;
    liveValue: string;
    liveBand: string;
    move: string;
    moveText: string;
    outcomes: Array<{title: string; lede: string}>;
  };
  display: {
    kicker: string;
    title: string[];
    lede: string;
    legal: string;
    ticker: string;
    captionLeft: string;
    captionRight: string;
  };
  coach: {
    kicker: string;
    title: string[];
    lede: string;
    legal: string;
    you: string;
    question: string;
    coachLabel: string;
    readLine: string;
    verdict: string;
    p1: string;
    p2: string;
    today: string;
    steps: string[];
    actPlan: string;
    actSleep: string;
    actAlarm: string;
    planKicker: string;
    planRead: string;
    planTitle: string;
    planLede: string;
    tasks: Array<{title: string; sub: string; meta?: string; done?: boolean}>;
    planFoot: string;
    regenerate: string;
    caps: Array<{kicker: string; title: string; lede: string}>;
  };
  nextBody: {
    kicker: string;
    title: string;
    mark: string;
    lede: string;
    break: string;
    feel: string;
    chase: string;
  };
  finishes: {
    kicker: string;
    price: string;
    title: string;
    lede: string;
    facts: Array<{value: string; label: string}>;
    white: string;
    black: string;
    once: string;
  };
  signals: {
    kicker: string;
    title: string;
    lede: string;
    note: string;
    items: string[];
  };
  close: {
    kicker: string;
    title: string[];
    lede: string;
    cta: string;
  };
  footer: {
    tag: string;
    product: string;
    legal: string;
    support: string;
    band: string;
    shop: string;
    science: string;
    faq: string;
    about: string;
    contact: string;
    journal: string;
    privacy: string;
    refund: string;
    shipping: string;
    terms: string;
    agreement: string;
    disclaimer: string;
    copy: string;
  };
};

const en: LandingCopy = {
  htmlLang: 'en',
  title: 'NEXTBODY · HOOP — The screenless band',
  description:
    'A band with no screen. It reads your heart, sleep, and training all day, and says it plainly in the NextBody app. $99. No subscription.',
  nav: {
    band: 'THE BAND',
    app: 'THE APP',
    science: 'SCIENCE',
    signIn: 'SIGN IN',
    getHoop: 'GET HOOP',
  },
  hero: {
    kicker: 'NEXTBODY · HOOP · THE SCREENLESS BAND',
    title: ['BUILD YOUR', 'NEXT BODY.'],
    lede: 'A band with no screen. It reads your heart, sleep, and training all day, and says it plainly in the app.',
    cta: 'Get HOOP — $99',
    noSub: 'No subscription. Ever.',
    floor: ['NO SCREEN', '5 DAYS PER CHARGE', '$99 · NO SUBSCRIPTION', 'READ IN THE APP'],
  },
  gallery: {
    kicker: 'THE OBJECT',
    title: ['Nothing to look at.', 'Everything to feel.'],
    lede: 'A brushed steel frame around a woven loop. No glass, no glow. The band is the whole design.',
    note: 'Six shots · drop renders in',
    sensorLabel: '04 · MACRO',
    sensorRatio: '4:5',
  },
  highlights: {
    kicker: 'HOOP',
    title: 'Get the highlights.',
    cards: [
      {kicker: 'AIR', title: 'So light you forget it is there.'},
      {kicker: 'WATER', title: 'Swim in it. Shower in it. Keep it on.'},
      {kicker: 'THREE NUMBERS', title: 'When to train. How much to eat.'},
      {kicker: 'BODY SCAN', title: 'Body fat from the wrist. No scale.'},
      {kicker: 'AI COACH', title: 'Reads your night. Plans your day.'},
      {kicker: 'AI DISPLAY', title: 'Ask out loud. It draws the screen.'},
    ],
    triad: [
      {value: '72%', label: 'BODY BATTERY'},
      {value: '14.9', label: 'TRAINING'},
      {value: '-728', label: 'CALORIES'},
    ],
    scan: {
      fat: '21.4',
      fatUnit: '%',
      fatLabel: 'BODY FAT',
      bmi: '21.3',
      bmiLabel: 'BMI',
    },
    coach: {
      question: 'Why am I so tired today?',
      kicker: 'AI COACH',
      answer: 'Short night. Take today light.',
      action: 'Adjust today’s plan',
    },
    aiDisplay: {
      question: 'Show me the nights I actually slept enough.',
      nights: '9',
      caption: 'NIGHTS OVER 7H · SEPTEMBER',
    },
  },
  appRead: {
    title: 'See your state at a glance.',
    lede: "Body Battery, last night's sleep, heart rate, and stress — all in the real NextBody.",
    note: 'For iPhone.',
    cta: 'See the App',
  },
  radar: {
    kicker: 'THREE CORE NUMBERS',
    title: ['Three numbers', 'run the cut.'],
    lede: 'Body Battery tells you how much you have left to spend today. Training tells you how hard to go. Calories tells you how much to eat.',
  },
  composition: {
    kicker: 'Composition',
    title: 'Read your body live.',
    lede: 'Fat, muscle, water, and bone — scanned from the wrist. The first scan is day zero. Scan again anytime.',
    phoneTitle: 'Your baseline',
    phoneLede: 'First scan complete — this is day zero.',
    phoneCta: 'Enter NEXTBODY',
    phoneHint: 'Scan again anytime from the Device page',
  },
  stress: {
    title: 'See stress as it happens.',
    lede: "HOOP reads cortisol-linked stress on the wrist — live, not after the fact. The coach names what's climbing, why it matters, and the next move that brings it down.",
    live: 'LIVE STRESS',
    liveValue: '32',
    liveBand: 'MID',
    move: 'THE MOVE',
    moveText: 'Walk eight minutes. Then sit still for four.',
    outcomes: [
      {title: 'FAT', lede: 'comes off when cortisol stays down'},
      {title: 'HRV', lede: 'climbs when you recover on time'},
      {title: 'SLEEP', lede: 'longer nights when the load drops'},
    ],
  },
  display: {
    kicker: 'THE DISPLAY',
    title: ['Every face', 'is generated.'],
    lede: "One screen. The model draws the face — a ring, a lift line, last night's sleep, a charge. The wrist keeps the numbers. Nothing on this display is a template.",
    legal:
      'For people 18 and over. HOOP is not a medical device. It does not take an ECG, and it does not diagnose.',
    ticker: 'LINE · DAYS · RING · SLEEP · FUEL · HEAT · BATTERY · GAUGE · ZONES',
    captionLeft: 'WRITTEN BY THE MODEL · 9 OF 34 FACES',
    captionRight: 'ONE SCREEN · THE MODEL DRAWS THE REST',
  },
  coach: {
    kicker: 'THE COACH',
    title: ['A coach that reads', 'before it speaks.'],
    lede: 'Every answer starts from your own night, HRV, training load, and meals. The coach cites what it read, says what it means, and gives you one plan for today.',
    legal:
      'For people 18 and over. HOOP is not a medical device. It does not take an ECG, and it does not diagnose.',
    you: '12:54 · YOU',
    question: 'Why am I so tired today?',
    coachLabel: 'AI COACH',
    readLine: 'READ SLEEP · HRV · LOAD · BATTERY',
    verdict: 'A short night, and your HRV has not come back yet.',
    p1: 'You slept 5 h 12 m — 1 h 40 m under your weekly average. Night HRV came in at 31 ms, the second night down from 38. Your body battery started the day at 61, not the 78 you usually wake with.',
    p2: 'Training load is fine at 12.4. This is a recovery problem, not a fitness one. Today should be light.',
    today: 'TODAY',
    steps: [
      'Keep the session in Zone 2, 30 minutes at most',
      'Move it to after 16:00, when your battery has climbed',
      'Lights out by 22:30 — the night is what fixes this',
    ],
    actPlan: 'Adjust today’s plan',
    actSleep: 'Show the sleep correlation',
    actAlarm: 'Set a 22:30 band alarm',
    planKicker: 'TODAY · 4 TASKS',
    planRead: 'AI READ SEP 4 → SEP 6',
    planTitle: 'A recovery day that still moves.',
    planLede:
      "Sleep was short and HRV is two nights down, so the session stays easy and late. The calorie gap holds. The night is what fixes this.",
    tasks: [
      {title: 'Log breakfast before 09:30', sub: 'Done at 08:12 · 331 kcal', done: true},
      {
        title: 'Zone 2 only, 30 minutes, after 16:00',
        sub: 'Wait for the battery to climb before you spend it',
        meta: 'BATTERY 61 AT WAKE · LOAD 12.4',
      },
      {
        title: '40 g protein at lunch, keep the gap at −500',
        sub: 'Tired days overeat at night. Front-load it.',
        meta: 'YESTERDAY −728 · SLEEP 5:12',
      },
      {
        title: 'Lights out by 22:30',
        sub: 'Band alarm is set. The night is what fixes this.',
        meta: 'HRV 38 → 31 · TWO NIGHTS DOWN',
      },
    ],
    planFoot:
      "Generated once on your first swipe up. Ticks are yours. Tomorrow's plan reads them.",
    regenerate: 'REGENERATE',
    caps: [
      {
        kicker: 'READS',
        title: 'Your night, your HRV, your load',
        lede: 'Before it answers, it pulls the same instruments you see on page two.',
      },
      {
        kicker: 'PLANS',
        title: 'Rewrites today, not your life',
        lede: 'One plan for the day in front of you. Sessions move, meals shift, bedtime is named.',
      },
      {
        kicker: 'ACTS',
        title: 'Sets the band from the thread',
        lede: 'Ask for a weekday alarm or a meal log and it is written to HOOP, no menu.',
      },
    ],
  },
  nextBody: {
    kicker: 'The next body',
    title: 'Build the next one.',
    mark: 'BUILD YOUR NEXTBODY',
    lede: 'The one ahead of you does not wait.',
    break: 'BREAK',
    feel: 'FEEL',
    chase: 'CHASE',
  },
  finishes: {
    kicker: 'TWO FINISHES',
    price: '$99',
    title: 'No subscription.',
    lede: 'Memberships in this category start at $239 a year. HOOP is $99 once — black or white — so more people can actually manage their body.',
    facts: [
      {value: '$99', label: 'ONCE'},
      {value: '$0', label: 'PER MONTH'},
      {value: '2', label: 'FINISHES'},
    ],
    white: 'WHITE',
    black: 'BLACK',
    once: '$99 · once',
  },
  signals: {
    kicker: 'What it reads',
    title: 'Twelve signals.',
    lede: 'HOOP does not run other apps. It reads twelve kinds of data — the three numbers that run the day, eight instruments on the wrist, and one scan you start yourself.',
    note: 'Night HRV lives on Sleep. No blood pressure. No ECG.',
    items: [
      'BODY BATTERY',
      'TRAINING LOAD',
      'SLEEP',
      'HEART',
      'BLOOD OXYGEN',
      'STRESS',
      'TEMPERATURE',
      'CALORIES',
      'STEPS',
      'DISTANCE',
      'ACTIVE ENERGY',
      'COMPOSITION',
    ],
  },
  close: {
    kicker: 'YOUR MOVE',
    title: ['BUILD YOUR', 'NEXTBODY.'],
    lede: 'The next version of you is already under the skin. HOOP just makes it visible.',
    cta: 'Get HOOP — $99',
  },
  footer: {
    tag: 'The screenless band. The body, read.',
    product: 'PRODUCT',
    legal: 'LEGAL',
    support: 'SUPPORT',
    band: 'The Band',
    shop: 'Shop',
    science: 'Science',
    faq: 'FAQ',
    about: 'About',
    contact: 'Contact',
    journal: 'Journal',
    privacy: 'Privacy Policy',
    refund: 'Refund Policy',
    shipping: 'Shipping Policy',
    terms: 'Terms of Service',
    agreement: 'User Agreement',
    disclaimer: '18+. Not a medical device. No ECG.',
    copy: '© 2026 NextBody',
  },
};

const zh: LandingCopy = {
  htmlLang: 'zh-Hans',
  title: 'NEXTBODY · HOOP — 无屏手环',
  description:
    '一条没有屏幕的手环。它整天读你的心率、睡眠和训练，然后在 NextBody App 里把话说清楚。$99，永不订阅。',
  nav: {
    band: '手环',
    app: 'App',
    science: '科学依据',
    signIn: '登录',
    getHoop: '购买 HOOP',
  },
  hero: {
    kicker: 'NEXTBODY · HOOP · 无屏手环',
    title: ['打造', '下一副身体。'],
    lede: '一条没有屏幕的手环。它整天读你的心率、睡眠和训练，然后在 App 里把话说清楚。',
    cta: '购买 HOOP — $99',
    noSub: '永不订阅。',
    floor: ['没有屏幕', '一次充电 5 天', '$99 · 无订阅', '在 App 里读'],
  },
  gallery: {
    kicker: '这件东西',
    title: ['没什么可看。', '全在身上。'],
    lede: '拉丝钢框架，包住一圈编织表带。没有玻璃，没有发光。手环本身就是全部设计。',
    note: '六张图 · 渲染稿待放入',
    sensorLabel: '04 · MACRO',
    sensorRatio: '4:5',
  },
  highlights: {
    kicker: 'HOOP',
    title: '先看重点。',
    cards: [
      {kicker: '轻', title: '轻到忘了它在手上。'},
      {kicker: '水', title: '游泳戴，洗澡戴，一直戴着。'},
      {kicker: '三个数', title: '什么时候练，吃多少。'},
      {kicker: '身体成分', title: '手腕上量体脂，不用体脂秤。'},
      {kicker: 'AI 教练', title: '读你的夜，排你的天。'},
      {kicker: 'AI 表盘', title: '开口问。它画出屏幕。'},
    ],
    triad: [
      {value: '72%', label: 'BODY BATTERY'},
      {value: '14.9', label: 'TRAINING'},
      {value: '-728', label: 'CALORIES'},
    ],
    scan: {
      fat: '21.4',
      fatUnit: '%',
      fatLabel: 'BODY FAT',
      bmi: '21.3',
      bmiLabel: 'BMI',
    },
    coach: {
      question: '我今天怎么这么累？',
      kicker: 'AI 教练',
      answer: '夜太短。今天轻一点。',
      action: '调整今天的计划',
    },
    aiDisplay: {
      question: '把我真正睡够的那些夜找出来。',
      nights: '9',
      caption: '超过 7 小时的夜 · 九月',
    },
  },
  appRead: {
    title: '一眼看清今天的状态。',
    lede: '身体电量、昨晚的睡眠、心率和压力——全在真实的 NextBody 里。',
    note: '支持 iPhone。',
    cta: '看 App',
  },
  radar: {
    kicker: '三大核心指标',
    title: ['三位一体', '检测核心减脂'],
    lede: 'Body Battery 让你知道今天还能测试、还能练多久。Training 告诉你该练到多少。Calories 告诉你今天该吃到多少。',
  },
  composition: {
    kicker: '身体成分',
    title: '实时读你的身体。',
    lede: '脂肪、肌肉、水分和骨量——从手腕扫出来。第一次扫描就是零点，之后随时可以再扫。',
    phoneTitle: '你的基线',
    phoneLede: '首次扫描完成——这是第零天。',
    phoneCta: '进入 NEXTBODY',
    phoneHint: '随时可在设备页里再扫一次',
  },
  stress: {
    title: '压力，发生时就看见。',
    lede: 'HOOP 在手腕上读与皮质醇相关的压力——是实时的，不是事后的。教练会告诉你什么在往上走、为什么要紧，以及下一步怎么把它压下去。',
    live: 'LIVE STRESS',
    liveValue: '32',
    liveBand: 'MID',
    move: 'THE MOVE',
    moveText: '走八分钟。然后静坐四分钟。',
    outcomes: [
      {title: 'FAT', lede: '皮质醇下来，脂肪才会掉'},
      {title: 'HRV', lede: '恢复准时，HRV 才会涨'},
      {title: 'SLEEP', lede: '负荷下来，夜晚才会变长'},
    ],
  },
  display: {
    kicker: '关于表盘',
    title: ['每一张表盘', '都是生成的。'],
    lede: '只有一块屏。模型自己画出表盘——一个环、一条抬升曲线、昨晚的睡眠、一格电。数字留在手腕上。这块屏上没有任何一样东西来自模板。',
    legal: '适用于 18 岁以上人群。HOOP 不是医疗器械，不做心电图，也不做诊断。',
    ticker: 'LINE · DAYS · RING · SLEEP · FUEL · HEAT · BATTERY · GAUGE · ZONES',
    captionLeft: 'WRITTEN BY THE MODEL · 9 OF 34 FACES',
    captionRight: 'ONE SCREEN · THE MODEL DRAWS THE REST',
  },
  coach: {
    kicker: '关于教练',
    title: ['先把你读懂，', '再开口。'],
    lede: '每一句回答都从你自己的睡眠、HRV、训练负荷和饮食出发。教练会说清它读到了什么、这意味着什么，然后给你今天的一份计划。',
    legal: '适用于 18 岁以上人群。HOOP 不是医疗器械，不做心电图，也不做诊断。',
    you: '12:54 · 你',
    question: '我今天怎么这么累？',
    coachLabel: 'AI 教练',
    readLine: '已读 睡眠 · HRV · 负荷 · 电量',
    verdict: '昨晚太短，而且你的 HRV 还没回来。',
    p1: '你只睡了 5 小时 12 分——比周平均少 1 小时 40 分。夜间 HRV 是 31 ms，比前一晚的 38 又低了一档。今天的身体电量从 61 开始，而不是你平时醒来的 78。',
    p2: '训练负荷 12.4，没问题。这是恢复的问题，不是体能的问题。今天应该练轻一点。',
    today: '今天',
    steps: [
      '把训练控制在 Z2，最多 30 分钟',
      '挪到 16:00 之后，那时电量已经回来了',
      '22:30 前熄灯——真正解决问题的是这一夜',
    ],
    actPlan: '调整今天的计划',
    actSleep: '看看和睡眠的相关性',
    actAlarm: '在手环上设 22:30 闹钟',
    planKicker: '今天 · 4 项',
    planRead: 'AI 读取 9.4 → 9.6',
    planTitle: '一个仍然动起来的恢复日。',
    planLede: '睡得短，HRV 连着两晚往下走，所以今天的训练放轻、往后挪。热量缺口保持不变。真正解决问题的是这一夜。',
    tasks: [
      {title: '09:30 前记录早餐', sub: '08:12 已完成 · 331 kcal', done: true},
      {
        title: '只练 Z2，30 分钟，16:00 之后',
        sub: '等电量回来了再花掉它',
        meta: '醒来电量 61 · 负荷 12.4',
      },
      {
        title: '午餐补 40 g 蛋白，缺口保持在 −500',
        sub: '累的日子晚上容易吃多，把量提前。',
        meta: '昨天 −728 · 睡眠 5:12',
      },
      {
        title: '22:30 前熄灯',
        sub: '手环闹钟已设好。真正解决问题的是这一夜。',
        meta: 'HRV 38 → 31 · 连着两晚下滑',
      },
    ],
    planFoot: '在你第一次上滑时生成一次。勾选是你自己的。明天的计划会读它们。',
    regenerate: '重新生成',
    caps: [
      {
        kicker: '读',
        title: '你的夜、你的 HRV、你的负荷',
        lede: '开口之前，它先调出你在第二页看到的那些仪表。',
      },
      {
        kicker: '排',
        title: '重写的是今天，不是你的人生',
        lede: '只给你眼前这一天一份计划。训练可以挪，饮食可以调，几点睡会说清楚。',
      },
      {
        kicker: '做',
        title: '在对话里直接设置手环',
        lede: '让它设一个工作日闹钟，或记一顿饭，它会直接写进 HOOP，不用翻菜单。',
      },
    ],
  },
  nextBody: {
    kicker: 'The next body',
    title: '打造下一副身体',
    mark: 'BUILD YOUR NEXTBODY',
    lede: '前面那一副，不会等你。',
    break: 'BREAK',
    feel: 'FEEL',
    chase: 'CHASE',
  },
  finishes: {
    kicker: '两种配色',
    price: '$99',
    title: '无需订阅。',
    lede: '同类产品的会员费一年从 $239 起。HOOP 只要 $99，一次付清——黑色或白色——让更多人真的管得起自己的身体。',
    facts: [
      {value: '$99', label: '一次'},
      {value: '$0', label: '每月'},
      {value: '2', label: '种配色'},
    ],
    white: 'WHITE',
    black: 'BLACK',
    once: '$99 · once',
  },
  signals: {
    kicker: '它读什么',
    title: '十二种数据。',
    lede: 'HOOP 不跑别的 App。它读十二种数据——管住一天的三个数、手腕上的八项仪表，以及一次由你自己发起的扫描。',
    note: '夜间 HRV 归在睡眠里。不测血压，不做心电图。',
    items: [
      'BODY BATTERY',
      'TRAINING LOAD',
      'SLEEP',
      'HEART',
      'BLOOD OXYGEN',
      'STRESS',
      'TEMPERATURE',
      'CALORIES',
      'STEPS',
      'DISTANCE',
      'ACTIVE ENERGY',
      'COMPOSITION',
    ],
  },
  close: {
    kicker: '轮到你了',
    title: ['打造你的', 'NEXTBODY'],
    lede: '下一个版本的你，已经在皮肤底下了。HOOP 只是让它被看见。',
    cta: '购买 HOOP — $99',
  },
  footer: {
    tag: '无屏手环。身体，被读懂。',
    product: '产品',
    legal: '法律',
    support: '支持',
    band: '手环',
    shop: '商店',
    science: '科学依据',
    faq: '常见问题',
    about: '关于',
    contact: '联系',
    journal: '手记',
    privacy: '隐私政策',
    refund: '退款政策',
    shipping: '配送政策',
    terms: '服务条款',
    agreement: '用户协议',
    disclaimer: '18 岁以上。非医疗器械，不做心电图。',
    copy: '© 2026 NextBody',
  },
};

export const LANDING: Record<LandingLocale, LandingCopy> = {en, zh};

export function landingCopy(locale: LandingLocale): LandingCopy {
  return LANDING[locale];
}
