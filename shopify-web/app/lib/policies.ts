import type {ShopLocale} from './locale';

export type PolicyHandle =
  | 'privacy-policy'
  | 'user-agreement'
  | 'terms-of-service'
  | 'refund-policy'
  | 'shipping-policy';

export type PolicyPage = {
  handle: PolicyHandle;
  title: {en: string; zh: string};
  lede: {en: string; zh: string};
  updated: string;
  sections: Array<{heading: {en: string; zh: string}; body: {en: string[]; zh: string[]}}>;
};

const UPDATED = '2026-09-08';

export const POLICIES: PolicyPage[] = [
  {
    handle: 'privacy-policy',
    title: {en: 'Privacy Policy', zh: '隐私政策'},
    lede: {
      en: 'How the shop, the app and the band handle what they learn about you — collected, used, kept, deleted.',
      zh: '商店、App 和手环怎么对待它们知道的关于你的一切 —— 收集、使用、保留、删除。',
    },
    updated: UPDATED,
    sections: [
      {
        heading: {en: 'Who we are', zh: '我们是谁'},
        body: {
          en: [
            'NextBody makes the HOOP band and the NextBody app, and runs this shop at nextbody.ai. This policy covers the website, the shop, the account you open here, and the health data the app keeps for you.',
            'It is written to be read once, in full, without a lawyer. Where a term has a legal meaning we say the plain thing next to it.',
            'Questions about anything on this page go to privacy@nextbody.ai.',
          ],
          zh: [
            'NextBody 做 HOOP 手环和 NextBody App，并运营 nextbody.ai 上的商店。本政策覆盖网站、商店、你在这里创建的账户，以及 App 为你保存的健康数据。',
            '它写成一次就能读完的样子，不需要律师在旁边。凡是有法律含义的词，我们都在旁边说一遍人话。',
            '本页任何问题请写 privacy@nextbody.ai。',
          ],
        },
      },
      {
        heading: {en: 'What we collect', zh: '我们收集什么'},
        body: {
          en: [
            'Account: the email address you sign in with, a hashed password, and the display name you choose. We never store a readable password.',
            'Orders: name, email, shipping address, the items you bought, and the last four digits of the card. The full card number goes to the payment processor and never touches our servers.',
            'Health data from HOOP: heart rate, heart rate variability, stress, skin temperature, blood oxygen at night, sleep stages, steps, distance, active energy, training load, body battery, and the body composition scans you start yourself. Plus the meals, weights, and notes you type in.',
            'Technical: IP address, browser or app version, and timestamps, kept so we can find abuse and fix crashes.',
            'Support: whatever you write to us, and our reply.',
          ],
          zh: [
            '账户：你登录用的邮箱、经过哈希的密码，以及你自己填的显示名。我们不会保存可读的明文密码。',
            '订单：姓名、邮箱、收货地址、买了什么，以及卡号后四位。完整卡号交给支付机构，不进我们的服务器。',
            'HOOP 的健康数据：心率、心率变异性、压力、皮肤温度、夜间血氧、睡眠分期、步数、距离、活动能量、训练负荷、身体电量，以及你自己发起的身体成分扫描。还有你自己输入的饮食、体重和备注。',
            '技术信息：IP 地址、浏览器或 App 版本、时间戳。留着是为了发现滥用和修崩溃。',
            '支持：你写给我们的内容，以及我们的回复。',
          ],
        },
      },
      {
        heading: {en: 'What we do with it', zh: '我们拿它做什么'},
        body: {
          en: [
            'Health data is used to compute your day — the battery, the load, the night, the plan — and to answer you when you ask the coach. That is the product. It is not used for advertising, and it is not sold. It has no price.',
            'Order and account data is used to take the order, ship it, answer support, and keep the books.',
            'Technical data is used for security and reliability. Aggregate counts — how many people opened the app, how often a screen crashed — never carry your name or your readings.',
          ],
          zh: [
            '健康数据用来算出你的一天 —— 电量、负荷、夜晚、计划 —— 以及在你问教练时回答你。这就是产品本身。它不用于广告，也不出售。它没有标价。',
            '订单和账户数据用于接单、发货、回复支持和记账。',
            '技术数据用于安全和稳定。汇总数字 —— 多少人打开过 App、某个页面崩了多少次 —— 不带你的名字，也不带你的读数。',
          ],
        },
      },
      {
        heading: {en: 'The coach and the model', zh: '教练与模型'},
        body: {
          en: [
            'When you ask the coach a question, the question and the readings it needs for that answer are sent to the model that writes the reply. It reads before it speaks — the night, the HRV, the load, the meals — and it cites what it read.',
            'The model provider processes that text to produce your answer and for nothing else. Your readings are not used to train a third-party model.',
            'If you never open the coach, nothing goes to a model.',
          ],
          zh: [
            '你向教练提问时，问题以及回答这条问题所需的读数会发给写回复的模型。它先读再说 —— 昨晚、HRV、负荷、饮食 —— 并且会说明自己读了什么。',
            '模型服务方只为生成这条回答而处理这些文本，不做别的。你的读数不会被拿去训练第三方模型。',
            '你从不打开教练，就没有任何东西发给模型。',
          ],
        },
      },
      {
        heading: {en: 'Cookies', zh: 'Cookie'},
        body: {
          en: [
            'The shop sets one httpOnly session cookie. It holds your cart, your language, your signed-in state, and your test orders. It stays on this site and expires when the session does.',
            'There are no advertising pixels and no third-party trackers on this storefront. Nothing here follows you to another site.',
          ],
          zh: [
            '商店只设一个 httpOnly 会话 cookie，里面装购物车、语言、登录状态和测试订单。它只属于本站，会话结束即过期。',
            '本店没有广告像素，没有第三方追踪器。这里的任何东西都不会跟着你去别的网站。',
          ],
        },
      },
      {
        heading: {en: 'Why we are allowed to', zh: '处理的依据'},
        body: {
          en: [
            'To take an order and run your account, we process what the contract with you needs.',
            'For health data we rely on your explicit consent, given when you pair a band and turned off when you unpair or delete. Consent you can take back is the only kind worth having.',
            'For security logs and fraud checks we rely on our legitimate interest in keeping the service standing. For tax and accounting records, on the law that requires them.',
          ],
          zh: [
            '为了接单和运行你的账户，我们处理履行合同所必需的信息。',
            '健康数据依据的是你的明示同意 —— 配对手环时给出，解绑或删除时收回。能收回的同意才算同意。',
            '安全日志和风控依据的是我们让服务活着的正当利益。税务和会计记录依据的是法律要求。',
          ],
        },
      },
      {
        heading: {en: 'Who else sees it', zh: '谁还会看到'},
        body: {
          en: [
            'A short list of processors, each bound by contract to use the data only for the job we hired them for: hosting and database, the model provider behind the coach, the payment processor, the carrier that delivers your parcel, and the mail service that sends receipts.',
            'We do not sell personal information and we do not share it with data brokers. If a law or a court orders disclosure, we comply and tell you unless we are forbidden to.',
            'If the company is ever sold or merged, the data moves under this same policy, and we say so before it happens.',
            'Our servers and processors may sit outside your country. Transfers use the safeguards the law asks for — standard contractual clauses or an adequacy decision.',
          ],
          zh: [
            '很短的一份处理方名单，每一家都受合同约束，只能为我们委托的事使用数据：托管与数据库、教练背后的模型服务方、支付机构、送包裹的承运商，以及发收据的邮件服务。',
            '我们不出售个人信息，也不与数据经纪商共享。若法律或法院要求披露，我们会照办，并在允许的前提下告诉你。',
            '若公司被出售或合并，数据在同一份政策之下转移，并且我们会在此之前说明。',
            '我们的服务器和处理方可能不在你所在的国家。跨境传输采用法律要求的保障措施 —— 标准合同条款或充分性认定。',
          ],
        },
      },
      {
        heading: {en: 'How long we keep it', zh: '保留多久'},
        body: {
          en: [
            'Health data: until you delete it or close the account. Deleting a day deletes it. Closing the account deletes all of it within 30 days, minus backups, which roll off within 90.',
            'Orders and invoices: as long as tax law requires, which in most places is five to seven years.',
            'Technical logs: 90 days. Support mail: 24 months.',
          ],
          zh: [
            '健康数据：保留到你删除它或注销账户为止。删掉某一天就是删掉。注销账户后 30 天内全部删除；备份除外，备份在 90 天内滚动清除。',
            '订单和发票：保留到税法要求的年限，多数地区是五到七年。',
            '技术日志：90 天。支持邮件：24 个月。',
          ],
        },
      },
      {
        heading: {en: 'What you can ask for', zh: '你可以要求什么'},
        body: {
          en: [
            'A copy of everything we hold, in a file you can open. A correction. A deletion. An export of your readings. A stop to any processing based on consent.',
            'Write to privacy@nextbody.ai from the address on the account. We answer within 30 days and we do not charge for it.',
            'Depending on where you live, the GDPR, the UK GDPR, the CCPA, or the PIPL gives you these rights by name, plus the right to complain to your own regulator. You do not have to go through us first.',
            'Signing out clears the account from this browser. Clearing site data clears the cart and any test orders on this device.',
          ],
          zh: [
            '一份我们持有的全部数据副本，格式你能打开。更正。删除。导出你的读数。停止任何基于同意的处理。',
            '用账户上的邮箱写信到 privacy@nextbody.ai。我们 30 天内答复，不收费。',
            '按你所在地区，GDPR、英国 GDPR、CCPA 或《个人信息保护法》都会逐条给你这些权利，另外还有向监管机构投诉的权利。你不必先经过我们。',
            '退出登录会清掉这个浏览器里的账户。清除站点数据会清掉本设备上的购物车和测试订单。',
          ],
        },
      },
      {
        heading: {en: 'Under 18', zh: '未满 18 岁'},
        body: {
          en: [
            'HOOP is for people 18 and over. We do not knowingly collect anything from anyone younger.',
            'If you believe a minor has an account, write to privacy@nextbody.ai and we delete it and its readings.',
          ],
          zh: [
            'HOOP 面向 18 岁及以上人群。我们不会在知情的情况下收集更年幼者的任何信息。',
            '若你认为有未成年人开了账户，请写信到 privacy@nextbody.ai，我们会删除该账户及其读数。',
          ],
        },
      },
      {
        heading: {en: 'When this page changes', zh: '本页变更时'},
        body: {
          en: [
            'The date at the top is the date of the last change. For anything material — a new kind of data, a new processor, a new purpose — we say so in the app before it takes effect, and where the law asks for fresh consent, we ask again.',
          ],
          zh: [
            '页首的日期就是最后修改日期。凡是实质性变化 —— 新增数据类型、新增处理方、新增用途 —— 我们会在生效前在 App 里说明；法律要求重新取得同意的，我们会再问一次。',
          ],
        },
      },
    ],
  },
  {
    handle: 'user-agreement',
    title: {en: 'User Agreement', zh: '用户协议'},
    lede: {
      en: 'The agreement for the app, the account, and the band on your wrist.',
      zh: '关于 App、账户，以及你手腕上那条手环的协议。',
    },
    updated: UPDATED,
    sections: [
      {
        heading: {en: 'What this agreement covers', zh: '这份协议管什么'},
        body: {
          en: [
            'This is the agreement between you and NextBody for the NextBody app, your account, and the HOOP band once it is paired. Buying on this website is covered by the Terms of Service; how we handle data is covered by the Privacy Policy. The three are meant to be read together.',
            'You accept this agreement when you create an account or open the app. If you do not accept it, do not use the app — and if you already bought a band, the Refund Policy still stands.',
          ],
          zh: [
            '这是你与 NextBody 之间关于 NextBody App、你的账户以及配对后的 HOOP 手环的协议。在本站购买由《服务条款》管；数据怎么处理由《隐私政策》管。三份文件应当合起来读。',
            '你创建账户或打开 App 即接受本协议。不接受就不要使用 App —— 如果你已经买了手环，《退款政策》依然有效。',
          ],
        },
      },
      {
        heading: {en: 'Your account', zh: '你的账户'},
        body: {
          en: [
            'One account belongs to one person, 18 or over. Keep the sign-in to yourself; anything done from a signed-in session counts as done by you.',
            'Tell us at once if you lose control of the account. We can suspend an account that is being used to attack the service or another person, and we say why when we do.',
          ],
          zh: [
            '一个账户属于一个人，18 岁及以上。登录信息自己保管；从已登录会话做出的一切都算你做的。',
            '账户失控请立刻告诉我们。若某个账户被用来攻击服务或攻击他人，我们会停用它，并在停用时说明原因。',
          ],
        },
      },
      {
        heading: {en: 'Your data stays yours', zh: '数据始终是你的'},
        body: {
          en: [
            'The readings your body produces belong to you. You give us only the permission the product needs: to store them, to compute your day from them, and to show them back to you across your own devices. Nothing wider.',
            'You can export them at any time and you can delete them at any time. Deleting is not a support ticket you have to argue; it is a button, and it means gone.',
          ],
          zh: [
            '你的身体产生的读数归你。你给我们的授权仅限产品所需：保存它们、由它们算出你的一天、并在你自己的设备之间显示回来。不多一分。',
            '你随时可以导出，随时可以删除。删除不是要去跟客服吵的工单，它是一个按钮，按下就是没了。',
          ],
        },
      },
      {
        heading: {en: 'What the band reads', zh: '手环读什么'},
        body: {
          en: [
            'HOOP reads twelve signals on the wrist and holds them until the app collects them over Bluetooth. Body battery, training load and sleep run the day; heart, blood oxygen, stress, temperature, calories, steps, distance and active energy sit on the instruments. Body composition is a scan you start yourself.',
            'There is no blood pressure and no ECG. The band has no microphone and no camera, and it does not carry a GPS of its own — location, when a workout uses it, comes from the phone and only while that workout is running.',
          ],
          zh: [
            'HOOP 在手腕上读十二种数据，先存住，等 App 通过蓝牙来取。身体电量、训练负荷和睡眠管住一天；心率、血氧、压力、温度、热量、步数、距离和活动能量在仪表上。身体成分是一次由你发起的扫描。',
            '不测血压，不做心电图。手环没有麦克风、没有摄像头，也没有自己的 GPS —— 训练用到位置时，位置来自手机，而且只在那次训练进行时。',
          ],
        },
      },
      {
        heading: {en: 'The coach can be wrong', zh: '教练会说错'},
        body: {
          en: [
            'The coach reads your own night, HRV, load and meals before it answers, and it tells you what it read. It is still a model writing sentences. It can be confidently wrong about you.',
            'Treat its plan as a suggestion from something that has seen your numbers, not as an instruction from someone who has examined you. Judgment stays with you.',
            'Some answers are metered. If a daily allowance runs out, the app says so plainly instead of pretending the coach has nothing to say.',
          ],
          zh: [
            '教练在回答前会读你自己的夜晚、HRV、负荷和饮食，并会告诉你它读了什么。它终究是一个在写句子的模型，可能非常笃定地把你说错。',
            '把它的计划当成一个看过你数字的东西给的建议，而不是一个检查过你身体的人下的医嘱。判断权还在你手里。',
            '部分回答有额度。每日额度用完时，App 会直接说明，而不是假装教练没话讲。',
          ],
        },
      },
      {
        heading: {en: 'Not a medical device', zh: '不是医疗器械'},
        body: {
          en: [
            'HOOP is a wellness product for people 18 and over. It is not a medical device. It does not diagnose, treat, cure or prevent any disease, and it is not built to detect a heart attack, sleep apnoea, or any other condition.',
            'Do not use it to make a medical decision, and do not wait on it in an emergency. Call your local emergency number instead.',
            'If you are pregnant, have a pacemaker or another implanted device, or are under a doctor for a heart or sleep condition, ask that doctor before you use the readings for anything.',
          ],
          zh: [
            'HOOP 是面向 18 岁及以上人群的健康产品，不是医疗器械。它不诊断、不治疗、不治愈、不预防任何疾病，也不是为发现心梗、睡眠呼吸暂停或任何其他病症而设计的。',
            '不要用它做医疗决定，紧急情况下也不要等它。请拨打当地急救电话。',
            '若你怀孕、装有心脏起搏器或其他植入设备，或正因心脏、睡眠问题在医生处就诊，请先问过医生，再决定这些读数怎么用。',
          ],
        },
      },
      {
        heading: {en: 'How you may use it', zh: '你可以怎么用'},
        body: {
          en: [
            'Use the app and the band for yourself. Do not resell access, scrape the service, hammer the API, or take the firmware apart to run it on something else.',
            'Do not put someone else on your account, and do not use the app to give another person medical or training advice as if it were a professional service.',
          ],
          zh: [
            'App 和手环给你自己用。不要转售访问权、抓取服务、猛刷接口，也不要拆固件把它跑在别的东西上。',
            '不要把别人放进你的账户，也不要拿这个 App 去给别人提供医疗或训练建议，装作那是专业服务。',
          ],
        },
      },
      {
        heading: {en: 'What we owe you', zh: '我们欠你什么'},
        body: {
          en: [
            'A band that works, and an app that reads it, without a subscription for that core reading. App AI is NextBody Pro. What you bought as the band keeps working if you skip Pro.',
            'The service is offered as it is. Features move, screens change, and a release can carry a bug. We do not promise the app is available every minute, only that we act like people who intend it to be.',
            'Where the law lets us limit liability, our total liability to you is capped at what you paid for the band. Nothing here removes a right your own consumer law gives you.',
          ],
          zh: [
            '一条能用的手环、一个能读它的 App，核心读数不收订阅费。App 里的 AI 是 NextBody Pro。跳过 Pro，你买到的手环仍按今天的方式继续工作。',
            '服务按现状提供。功能会挪、界面会变、某个版本可能带 bug。我们不承诺 App 每分钟都在线，只承诺我们像真心想让它在线的人那样做事。',
            '在法律允许限制责任的范围内，我们对你的全部责任以你为手环支付的金额为上限。本协议不剥夺你所在地消费者法给你的任何权利。',
          ],
        },
      },
      {
        heading: {en: 'Ending it', zh: '结束'},
        body: {
          en: [
            'You can close the account in the app at any time. We delete the readings within 30 days and keep only what tax or accounting law makes us keep.',
            'We can end this agreement if you break it in a way that harms other people or the service. Unpairing a band does not close the account, and closing an account does not brick a band.',
            'This agreement is governed by the law of the place where NextBody is established, and by any consumer law of your own country that applies to you regardless. Before anyone files anything, write to shop@nextbody.ai — most of it is a misunderstanding that a reply fixes.',
          ],
          zh: [
            '你随时可以在 App 里注销账户。我们会在 30 天内删除读数，只保留税务或会计法律要求保留的部分。',
            '若你以伤害他人或伤害服务的方式违反本协议，我们可以终止协议。解绑手环不等于注销账户；注销账户也不会把手环变砖。',
            '本协议适用 NextBody 设立地的法律，同时适用你所在国家依法必然适用的消费者法。任何人提交任何东西之前，请先写 shop@nextbody.ai —— 多数情况是一次回复就能解开的误会。',
          ],
        },
      },
    ],
  },
  {
    handle: 'terms-of-service',
    title: {en: 'Terms of Service', zh: '服务条款'},
    lede: {
      en: 'The rules for buying on nextbody.ai — orders, price, warranty, and the test checkout.',
      zh: '在 nextbody.ai 购买的规则 —— 订单、价格、保修，以及测试结算。',
    },
    updated: UPDATED,
    sections: [
      {
        heading: {en: 'These terms', zh: '这份条款'},
        body: {
          en: [
            'These terms cover nextbody.ai and this storefront: browsing it, opening a shop account, and ordering. Using the shop means you accept them.',
            'The app, your account inside it, and the readings HOOP takes are covered by the User Agreement. Data is covered by the Privacy Policy.',
          ],
          zh: [
            '本条款覆盖 nextbody.ai 和这个店面：浏览、开通商店账户、下单。使用商店即表示接受。',
            'App、App 里的账户以及 HOOP 采集的读数由《用户协议》覆盖。数据由《隐私政策》覆盖。',
          ],
        },
      },
      {
        heading: {en: 'Who can order', zh: '谁可以下单'},
        body: {
          en: [
            'You must be 18 or over and able to enter a contract where you live. The address and contact details you give have to be real ones — a parcel cannot be delivered to a placeholder.',
            'We can decline or cancel an order, for example when a listing was wrong, stock ran out, or an order looks like fraud or resale at scale. If we cancel, you are not charged, or you are refunded in full.',
          ],
          zh: [
            '你必须年满 18 岁，并在你所在地具备订立合同的能力。填写的地址和联系方式必须是真实的 —— 包裹送不到一个占位符。',
            '我们可以拒绝或取消订单，例如商品信息出错、库存售罄，或订单看起来是欺诈或大规模转售。若由我们取消，你不会被扣款，或全额退回。',
          ],
        },
      },
      {
        heading: {en: 'The product and the price', zh: '产品与价格'},
        body: {
          en: [
            'HOOP is $99 once, in black or white. The knit nylon strap and the sport strap are both in the box. The app that reads the band is included. App AI is NextBody Pro at $6 / month.',
            'Prices are in US dollars and exclude any duty or import tax your country charges. Where sales tax or VAT applies, it is shown before you pay.',
            'Photography is photography. Finish and strap colour can differ slightly from a render on your screen.',
            'If a price or a spec is obviously wrong — a typo, a decimal in the wrong place — we can correct it and let you decide again before anything ships.',
          ],
          zh: [
            'HOOP 售价 $99，一次付清，黑色或白色。编织尼龙表带和运动表带都在盒里。读取手环的 App 随手环。App 里的 AI 是 NextBody Pro，每月 $6。',
            '价格以美元计，不含你所在国家征收的关税或进口税。适用销售税或增值税时，会在付款前显示。',
            '照片终归是照片。表面颜色和表带颜色与屏幕上的渲染可能略有差别。',
            '若价格或规格明显写错 —— 打字错误、小数点跑位 —— 我们可以更正，并在发货前让你重新决定。',
          ],
        },
      },
      {
        heading: {en: 'How an order works', zh: '订单怎么成立'},
        body: {
          en: [
            'Your order is an offer to buy. The confirmation email says we received it. The contract is made when we hand the parcel to the carrier, and the shipping notice is the moment it is made.',
            'Risk passes to you on delivery. Title passes when payment clears.',
          ],
          zh: [
            '你的订单是一份购买要约。确认邮件表示我们收到了。合同在我们把包裹交给承运商时成立，发货通知就是成立的那一刻。',
            '风险自签收时转移给你。所有权在款项结清时转移。',
          ],
        },
      },
      {
        heading: {en: 'This checkout is a test', zh: '本店结算是测试'},
        body: {
          en: [
            'Right now this storefront runs a closed test checkout. It accepts a card number so you can walk the whole path and see an order, but it does not charge the card, it does not reach a payment processor, and it does not create a shipment.',
            'Until a live checkout is switched on, the pages here are a description of the product, not an offer to sell.',
          ],
          zh: [
            '目前本店运行的是闭环测试结算。它接受卡号，只为让你把整条路径走完并看到订单，但不会扣款、不会到达支付机构，也不会产生发货。',
            '在正式结算打开之前，这里的页面是对产品的描述，不构成销售要约。',
          ],
        },
      },
      {
        heading: {en: 'Health, plainly', zh: '关于健康，把话说明'},
        body: {
          en: [
            'HOOP is for people 18 and over. It is not a medical device. It does not take an ECG, it does not measure blood pressure, and it does not diagnose, treat or prevent any disease.',
            'Nothing on this site is medical advice. If a number worries you, take it to a clinician, not to the internet.',
          ],
          zh: [
            'HOOP 面向 18 岁及以上人群。它不是医疗器械。不做心电图，不测血压，也不诊断、治疗或预防任何疾病。',
            '本站任何内容都不构成医疗建议。若某个数字让你担心，请拿去问医生，而不是问互联网。',
          ],
        },
      },
      {
        heading: {en: 'Your shop account', zh: '商店账户'},
        body: {
          en: [
            'The shop account holds your orders and addresses. It is separate from the health account in the app; the shop never sees your readings.',
            'Keep the password to yourself. Tell us if it leaks and we will lock the account.',
          ],
          zh: [
            '商店账户保存你的订单和地址。它与 App 里的健康账户是分开的；商店看不到你的读数。',
            '密码自己保管。若泄露请告诉我们，我们会锁定账户。',
          ],
        },
      },
      {
        heading: {en: 'What you may not do here', zh: '这里不能做的事'},
        body: {
          en: [
            'Do not scrape the site, script the checkout, probe it for holes without asking us first, or copy the text, photography, or the generated faces for your own product.',
            'Security researchers are welcome. Write to shop@nextbody.ai before you test anything, and we will answer.',
          ],
          zh: [
            '不要抓取本站、脚本刷结算、未经我们同意就扫描漏洞，也不要把这里的文案、摄影或生成的表盘搬进你自己的产品。',
            '欢迎安全研究者。测试之前请先写信到 shop@nextbody.ai，我们会回复。',
          ],
        },
      },
      {
        heading: {en: 'What belongs to whom', zh: '谁拥有什么'},
        body: {
          en: [
            'The NextBody name, the HOOP name, the industrial design, the software, the copy and the images on this site belong to NextBody or its licensors. Buying a band buys the band and a personal licence to use the software on it.',
            'The readings your body produces belong to you. That is in the User Agreement, and it does not change here.',
          ],
          zh: [
            'NextBody 名称、HOOP 名称、工业设计、软件、本站文案与图片归 NextBody 或其许可方所有。买手环买到的是手环本身，以及在其上使用软件的个人许可。',
            '你的身体产生的读数归你。这一条写在《用户协议》里，在这里不变。',
          ],
        },
      },
      {
        heading: {en: 'Warranty and liability', zh: '保修与责任'},
        body: {
          en: [
            'A new HOOP carries a 12-month limited warranty against manufacturing defects from the day it is delivered. Straps carry 6 months. Wear, water past the rated depth, drops, and anything opened up are not defects.',
            'To the extent the law allows, we are not liable for indirect or consequential loss, and our total liability for an order is capped at what you paid for it. Nothing here limits liability for death, personal injury caused by our negligence, or fraud, and nothing here takes away the statutory rights your own consumer law gives you.',
          ],
          zh: [
            '全新 HOOP 自签收之日起提供 12 个月制造缺陷有限保修。表带 6 个月。正常磨损、超出防水深度进水、跌落，以及任何被拆开过的情况，都不算缺陷。',
            '在法律允许的范围内，我们不对间接损失或后果性损失负责，对一笔订单的全部责任以你为其支付的金额为上限。本条不限制因我们过失造成的死亡或人身伤害的责任，也不限制欺诈责任，更不剥夺你所在地消费者法赋予的法定权利。',
          ],
        },
      },
      {
        heading: {en: 'Law, disputes, and changes', zh: '法律、争议与变更'},
        body: {
          en: [
            'These terms are governed by the law of the place where NextBody is established, together with any consumer law of your own country that applies to you regardless.',
            'Before a dispute becomes a filing, write to shop@nextbody.ai. We answer, and most of it ends there.',
            'We can change these terms. The date at the top is the date of the last change, and an order is always governed by the terms in force on the day it was placed.',
          ],
          zh: [
            '本条款适用 NextBody 设立地的法律，同时适用你所在国家依法必然适用的消费者法。',
            '在争议变成诉状之前，请先写信到 shop@nextbody.ai。我们会回复，多数事情就到此为止。',
            '我们可以修改本条款。页首日期是最后修改日期；每一笔订单始终适用下单当日生效的条款。',
          ],
        },
      },
    ],
  },
  {
    handle: 'refund-policy',
    title: {en: 'Refund Policy', zh: '退款政策'},
    lede: {
      en: 'Thirty days to change your mind. Twelve months if it is our fault.',
      zh: '三十天可以反悔。如果是我们的错，十二个月都算。',
    },
    updated: UPDATED,
    sections: [
      {
        heading: {en: 'Thirty days', zh: '三十天'},
        body: {
          en: [
            'You have 30 days from delivery to send a HOOP back for a full refund of the product price. It has to come back complete — band, both straps, charger, box — and in a condition someone could reasonably call unused.',
            'You do not have to explain why. A wrist is a personal thing and a band either suits it or does not.',
          ],
          zh: [
            '自签收起 30 天内，你可以把 HOOP 寄回并全额退回产品款。寄回时要齐全 —— 手环、两条表带、充电器、包装盒 —— 并且状态是一个正常人会称为「未使用」的状态。',
            '不必解释原因。手腕是很私人的东西，一条手环要么合适，要么不合适。',
          ],
        },
      },
      {
        heading: {en: 'How to start one', zh: '怎么发起'},
        body: {
          en: [
            'Write to shop@nextbody.ai with the order number. We reply with a return number and the address to send it to. Please do not post it back without that number — an unlabelled parcel is very hard to match to a person.',
            'Pack it so it survives the trip. Until it reaches us it is still your parcel, so keep the tracking.',
          ],
          zh: [
            '带上订单号写信到 shop@nextbody.ai。我们会回复一个退货编号和寄回地址。请不要在没有编号的情况下直接寄回 —— 没有标识的包裹很难对上人。',
            '包装要能撑过路上。在寄到我们这里之前，它仍是你的包裹，请保留运单号。',
          ],
        },
      },
      {
        heading: {en: 'Who pays the return', zh: '退货运费谁出'},
        body: {
          en: [
            'If the band is faulty or we sent the wrong thing, we pay both ways and you are not out of pocket.',
            'If you simply changed your mind, return shipping is yours. Original shipping is refunded only where the law says it must be.',
          ],
          zh: [
            '若手环有缺陷或我们发错了东西，来回运费都由我们承担，你不会自掏腰包。',
            '若只是改变主意，退货运费由你承担。原始运费只在法律要求退回时退回。',
          ],
        },
      },
      {
        heading: {en: 'When the money comes back', zh: '钱什么时候回来'},
        body: {
          en: [
            'We inspect the return the day it lands and issue the refund within 5 business days of accepting it. It goes back to the original payment method. Your bank usually adds 3 to 10 days of its own.',
            'If a return arrives short of parts or visibly used, we tell you what we found and what we can refund before we do anything.',
          ],
          zh: [
            '退货到达当天我们就会检查，确认后 5 个工作日内退款，原路退回。银行通常还要再加 3 到 10 天。',
            '若退回的东西缺件或明显使用过，我们会先告诉你我们看到了什么、能退多少，然后再动作。',
          ],
        },
      },
      {
        heading: {en: 'Faulty units', zh: '设备有问题'},
        body: {
          en: [
            'A manufacturing defect inside 12 months gets a repair, a replacement, or a refund — our choice first, yours if the first attempt does not fix it. Straps carry 6 months.',
            'Send a photo or a short video with the first email if you can. It usually saves a whole round trip.',
          ],
          zh: [
            '12 个月内出现制造缺陷，可以维修、更换或退款 —— 第一次由我们选择，若第一次没有解决，则由你选择。表带保 6 个月。',
            '第一封邮件里尽量附一张照片或一段短视频，通常能省下一整趟来回。',
          ],
        },
      },
      {
        heading: {en: 'What we cannot take back', zh: '不能退的情况'},
        body: {
          en: [
            'Straps that have been worn, unless they are faulty. Anything damaged by a drop, by water past the rated depth, or by being opened. Bands bought from someone who is not us. Anything outside the 30 days, unless it is a warranty claim.',
          ],
          zh: [
            '戴过的表带，除非有缺陷。因跌落、超出防水深度进水或被拆开而损坏的物品。从非我方渠道购买的手环。超过 30 天的退货请求，除非属于保修。',
          ],
        },
      },
      {
        heading: {en: 'Cancelling before it ships', zh: '发货前取消'},
        body: {
          en: [
            'Write within a few hours of ordering and we can usually stop it, change the address, or swap the colour. Once the label is printed the parcel has to travel, and it becomes a return.',
            'In the EU and the UK you also have a statutory 14-day right to withdraw, which runs alongside the 30 days above and is never shortened by it.',
          ],
          zh: [
            '下单后几小时内写信，我们通常还能拦下来、改地址或换颜色。运单一旦打印，包裹就得走完这一趟，然后按退货处理。',
            '在欧盟和英国，你另有法定的 14 天撤回权，与上面的 30 天并行，且绝不会被它缩短。',
          ],
        },
      },
      {
        heading: {en: 'On this test shop', zh: '在本测试店'},
        body: {
          en: [
            'Orders placed here are test orders. No payment is taken, so there is nothing to refund and no parcel to send back. The confirmation page is the end of the path.',
          ],
          zh: [
            '这里下的都是测试订单。没有扣款，因此没有可退的钱，也没有要寄回的包裹。确认页就是这条路径的终点。',
          ],
        },
      },
    ],
  },
  {
    handle: 'shipping-policy',
    title: {en: 'Shipping Policy', zh: '配送政策'},
    lede: {
      en: 'Where it goes, what it costs, how long it takes, and what happens when it goes wrong.',
      zh: '送到哪里、多少钱、多久到，以及出问题时怎么办。',
    },
    updated: UPDATED,
    sections: [
      {
        heading: {en: 'Where we send it', zh: '送到哪里'},
        body: {
          en: [
            'The live shop ships to the United States, Canada, the United Kingdom, the European Union, Switzerland, Norway, Australia, New Zealand, Japan, Korea, Singapore, Hong Kong, Taiwan and mainland China.',
            'Other destinations open as the customs paperwork is ready. If yours is not on the list, write to shop@nextbody.ai and we will say when.',
          ],
          zh: [
            '正式商店发往美国、加拿大、英国、欧盟、瑞士、挪威、澳大利亚、新西兰、日本、韩国、新加坡、中国香港、中国台湾和中国大陆。',
            '其他地区会在清关文件齐备后开放。若名单里没有你那边，请写 shop@nextbody.ai，我们会告诉你时间。',
          ],
        },
      },
      {
        heading: {en: 'What it costs', zh: '运费'},
        body: {
          en: [
            'Shipping is $8 on a strap-only cart. A cart of $99 or more — a single HOOP counts — ships free.',
            'Shipping is quoted before you pay. There is no handling fee bolted on at the end.',
          ],
          zh: [
            '只买表带时运费 $8。满 $99 免运费 —— 单独买一条 HOOP 就够。',
            '运费在付款前就报出来。最后不会再加什么手续费。',
          ],
        },
      },
      {
        heading: {en: 'How long it takes', zh: '要多久'},
        body: {
          en: [
            'Orders leave the warehouse in 2 to 4 business days. Transit is usually 3 to 5 days in the United States and 5 to 10 days everywhere else.',
            'We do not ship on weekends or local public holidays, and a launch week can add a day or two. If an order will be late, we write to you before you have to ask.',
          ],
          zh: [
            '订单在 2 到 4 个工作日内出库。在途通常美国境内 3 到 5 天，其他地区 5 到 10 天。',
            '周末和当地公共假日不发货，发售周可能再多一两天。若订单会延误，我们会在你开口问之前先写信告诉你。',
          ],
        },
      },
      {
        heading: {en: 'Tracking', zh: '追踪'},
        body: {
          en: [
            'A tracking number reaches you by email the moment the label is scanned. It can sit quiet for a day before the carrier updates it; that is the carrier, not the parcel.',
            'The same number is on the order page in your account.',
          ],
          zh: [
            '运单一被扫描，运单号就会发到你的邮箱。它可能有一天没有更新，那是承运商的节奏，不是包裹出了事。',
            '同一个单号也在你账户的订单页上。',
          ],
        },
      },
      {
        heading: {en: 'Duty and tax', zh: '关税和税费'},
        body: {
          en: [
            'Inside the United States, tax is calculated at checkout. Elsewhere, import duty and VAT are set by your own country and are yours to pay, unless the checkout collected them up front and said so.',
            'A parcel refused at customs comes back to us, and we refund the product price minus the shipping both ways.',
          ],
          zh: [
            '美国境内的税在结算时计算。其他地区的进口关税和增值税由你所在国家决定，由你承担，除非结算时已经代收并明确说明。',
            '在海关被拒收的包裹会退回我们，我们退还产品款，扣除来回运费。',
          ],
        },
      },
      {
        heading: {en: 'Wrong address, lost, or damaged', zh: '地址错、丢件、破损'},
        body: {
          en: [
            'Check the address on the confirmation email. We can change it before the label prints; after that it has to be redirected with the carrier, and some carriers charge for that.',
            'Tell us within 7 days if a parcel arrives damaged — a photo of the box helps. Tell us if tracking has not moved for 10 days and we open a case with the carrier; if it is genuinely lost we send another one.',
          ],
          zh: [
            '请核对确认邮件上的地址。运单打印前我们可以改；之后只能通过承运商改派，有些承运商会收费。',
            '包裹到达时若有破损，请在 7 天内告诉我们 —— 拍一张外箱照片会很有帮助。若运单 10 天没有更新，也请告诉我们，我们会向承运商开案；确认丢件的，我们再发一件。',
          ],
        },
      },
      {
        heading: {en: 'On this test shop', zh: '在本测试店'},
        body: {
          en: [
            'You can enter any supported country and see the rate and the total. Nothing is picked, packed or posted, and no carrier is ever contacted.',
          ],
          zh: [
            '你可以填任意受支持的国家或地区，看到运费和总价。但不会有人拣货、打包、投递，也不会联系任何承运商。',
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
