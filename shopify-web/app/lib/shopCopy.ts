import type {ShopLocale} from './locale';
import {TEST_DISCOUNT_CODE} from './shopMath';

export type ShopCopy = {
  nav: {
    band: string;
    shop: string;
    science: string;
    signIn: string;
    account: string;
    cart: string;
    getHoop: string;
    search: string;
    menu: string;
    close: string;
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
  shop: {
    kicker: string;
    title: string;
    lede: string;
    empty: string;
    view: string;
    from: string;
  };
  product: {
    add: string;
    buy: string;
    added: string;
    soldOut: string;
    shipping: string;
    shippingNote: string;
    legal: string;
    related: string;
    qty: string;
    color: string;
    inBox: string;
  };
  cart: {
    title: string;
    empty: string;
    continue: string;
    checkout: string;
    subtotal: string;
    discount: string;
    shipping: string;
    shippingFree: string;
    total: string;
    remove: string;
    code: string;
    apply: string;
    codeHint: string;
    codeOk: string;
    codeBad: string;
    qty: string;
  };
  checkout: {
    title: string;
    testBanner: string;
    contact: string;
    email: string;
    name: string;
    shipping: string;
    address1: string;
    address2: string;
    city: string;
    region: string;
    postal: string;
    country: string;
    phone: string;
    payment: string;
    card: string;
    expiry: string;
    cvc: string;
    cardHint: string;
    place: string;
    placing: string;
    empty: string;
    errorRequired: string;
    errorEmail: string;
    errorCard: string;
    errorExpiry: string;
    errorCvc: string;
    countries: Array<{id: string; label: string}>;
  };
  complete: {
    kicker: string;
    title: string;
    lede: string;
    order: string;
    test: string;
    continue: string;
    account: string;
  };
  account: {
    title: string;
    lede: string;
    email: string;
    name: string;
    enter: string;
    welcome: string;
    orders: string;
    noOrders: string;
    profile: string;
    addresses: string;
    save: string;
    saved: string;
    signOut: string;
    testNote: string;
    orderPaid: string;
  };
  search: {
    title: string;
    placeholder: string;
    submit: string;
    empty: string;
    results: string;
  };
  notFound: {
    title: string;
    lede: string;
    shop: string;
    home: string;
  };
  pages: {
    back: string;
  };
};

const en: ShopCopy = {
  nav: {
    band: 'THE BAND',
    shop: 'SHOP',
    science: 'SCIENCE',
    signIn: 'SIGN IN',
    account: 'ACCOUNT',
    cart: 'CART',
    getHoop: 'GET HOOP',
    search: 'SEARCH',
    menu: 'MENU',
    close: 'CLOSE',
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
  shop: {
    kicker: 'NEXTBODY',
    title: 'Get HOOP.',
    lede: '$99 once. No subscription. Black or white. Both straps in the box.',
    empty: 'Nothing in this collection yet.',
    view: 'View',
    from: 'From',
  },
  product: {
    add: 'Add to cart',
    buy: 'Buy now',
    added: 'Added to cart',
    soldOut: 'Sold out',
    shipping: 'FREE SHIPPING',
    shippingNote: 'HOOP ships free. 5–10 business days.',
    legal: '18+. Not a medical device. HOOP does not take an ECG and does not diagnose.',
    related: 'Also in the kit',
    qty: 'Qty',
    color: 'COLOR',
    inBox: 'IN THE BOX',
  },
  cart: {
    title: 'Cart',
    empty: 'The cart is empty. HOOP is $99 once.',
    continue: 'Continue shopping',
    checkout: 'Checkout',
    subtotal: 'Subtotal',
    discount: 'Discount',
    shipping: 'Shipping',
    shippingFree: 'Free',
    total: 'Total',
    remove: 'Remove',
    code: 'Discount code',
    apply: 'Apply',
    codeHint: `Try ${TEST_DISCOUNT_CODE} on this test shop.`,
    codeOk: 'Test discount applied.',
    codeBad: 'That code is not on this test shop.',
    qty: 'Qty',
  },
  checkout: {
    title: 'Checkout',
    testBanner: 'Test checkout — you will not be charged. No card is sent to a processor.',
    contact: 'Contact',
    email: 'Email',
    name: 'Full name',
    shipping: 'Shipping',
    address1: 'Address',
    address2: 'Apartment, suite (optional)',
    city: 'City',
    region: 'State / region',
    postal: 'Postal code',
    country: 'Country',
    phone: 'Phone (optional)',
    payment: 'Payment',
    card: 'Card number',
    expiry: 'MM / YY',
    cvc: 'CVC',
    cardHint: 'Use 4242 4242 4242 4242 or any 13–19 digit test number.',
    place: 'Place test order',
    placing: 'Placing…',
    empty: 'Add HOOP to the cart before checkout.',
    errorRequired: 'Fill in every required field.',
    errorEmail: 'Enter a valid email.',
    errorCard: 'Enter a test card number.',
    errorExpiry: 'Enter a future expiry as MM / YY.',
    errorCvc: 'Enter a 3 or 4 digit CVC.',
    countries: [
      {id: 'US', label: 'United States'},
      {id: 'CN', label: 'China'},
      {id: 'HK', label: 'Hong Kong'},
      {id: 'TW', label: 'Taiwan'},
      {id: 'JP', label: 'Japan'},
      {id: 'GB', label: 'United Kingdom'},
      {id: 'CA', label: 'Canada'},
      {id: 'AU', label: 'Australia'},
      {id: 'SG', label: 'Singapore'},
      {id: 'DE', label: 'Germany'},
    ],
  },
  complete: {
    kicker: 'TEST ORDER',
    title: 'HOOP is on its way — in this test.',
    lede: 'No payment was taken. This closes the buy flow so you can walk the site.',
    order: 'Order',
    test: 'Paid with test card',
    continue: 'Back to shop',
    account: 'View in account',
  },
  account: {
    title: 'Account',
    lede: 'A test sign-in. Email only — no password, no Shopify login.',
    email: 'Email',
    name: 'Name',
    enter: 'Enter',
    welcome: 'Welcome',
    orders: 'Orders',
    noOrders: 'No test orders yet.',
    profile: 'Profile',
    addresses: 'Address',
    save: 'Save',
    saved: 'Saved.',
    signOut: 'Sign out',
    testNote: 'Test account. Orders stay in this browser session.',
    orderPaid: 'Test paid',
  },
  search: {
    title: 'Search',
    placeholder: 'HOOP, band…',
    submit: 'Search',
    empty: 'Nothing matched. Try HOOP.',
    results: 'Results',
  },
  notFound: {
    title: 'This page is not here.',
    lede: 'The shop, the band, and the policies are.',
    shop: 'Go to shop',
    home: 'Home',
  },
  pages: {
    back: 'Back',
  },
};

const zh: ShopCopy = {
  nav: {
    band: '手环',
    shop: '商店',
    science: '科学依据',
    signIn: '登录',
    account: '账户',
    cart: '购物车',
    getHoop: '购买 HOOP',
    search: '搜索',
    menu: '菜单',
    close: '关闭',
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
  shop: {
    kicker: 'NEXTBODY',
    title: '购买 HOOP。',
    lede: '$99 一次付清。永不订阅。黑色或白色。盒内两条表带都有。',
    empty: '这个系列里还没有商品。',
    view: '查看',
    from: '起',
  },
  product: {
    add: '加入购物车',
    buy: '立即购买',
    added: '已加入购物车',
    soldOut: '已售罄',
    shipping: '免运费',
    shippingNote: 'HOOP 免运费。5–10 个工作日。',
    legal: '18 岁以上。HOOP 不是医疗器械，不做心电图，也不做诊断。',
    related: '还可以一起买',
    qty: '数量',
    color: '颜色',
    inBox: '盒内含',
  },
  cart: {
    title: '购物车',
    empty: '购物车是空的。HOOP 只要 $99。',
    continue: '继续逛',
    checkout: '去结算',
    subtotal: '小计',
    discount: '优惠',
    shipping: '运费',
    shippingFree: '免运费',
    total: '合计',
    remove: '移除',
    code: '优惠码',
    apply: '使用',
    codeHint: `测试店可用 ${TEST_DISCOUNT_CODE}。`,
    codeOk: '测试优惠已使用。',
    codeBad: '这个测试店没有这个码。',
    qty: '数量',
  },
  checkout: {
    title: '结算',
    testBanner: '测试结算 — 不会扣款。卡号不会发给任何支付机构。',
    contact: '联系方式',
    email: '邮箱',
    name: '姓名',
    shipping: '收货地址',
    address1: '地址',
    address2: '公寓、门牌（选填）',
    city: '城市',
    region: '省 / 州',
    postal: '邮编',
    country: '国家 / 地区',
    phone: '电话（选填）',
    payment: '付款',
    card: '卡号',
    expiry: '月 / 年',
    cvc: 'CVC',
    cardHint: '可用 4242 4242 4242 4242，或任意 13–19 位测试卡号。',
    place: '提交测试订单',
    placing: '提交中…',
    empty: '请先把 HOOP 加入购物车。',
    errorRequired: '请填完必填项。',
    errorEmail: '请输入有效邮箱。',
    errorCard: '请输入测试卡号。',
    errorExpiry: '请输入未过期的月 / 年。',
    errorCvc: '请输入 3 或 4 位 CVC。',
    countries: [
      {id: 'CN', label: '中国大陆'},
      {id: 'HK', label: '中国香港'},
      {id: 'TW', label: '中国台湾'},
      {id: 'US', label: '美国'},
      {id: 'JP', label: '日本'},
      {id: 'SG', label: '新加坡'},
      {id: 'GB', label: '英国'},
      {id: 'CA', label: '加拿大'},
      {id: 'AU', label: '澳大利亚'},
      {id: 'DE', label: '德国'},
    ],
  },
  complete: {
    kicker: '测试订单',
    title: 'HOOP 已下单 — 在这次测试里。',
    lede: '没有扣款。这条路径只是为了把购买流程走完。',
    order: '订单',
    test: '测试卡已记',
    continue: '回到商店',
    account: '在账户里查看',
  },
  account: {
    title: '账户',
    lede: '测试登录。只需要邮箱 — 没有密码，也不走 Shopify。',
    email: '邮箱',
    name: '姓名',
    enter: '进入',
    welcome: '你好',
    orders: '订单',
    noOrders: '还没有测试订单。',
    profile: '资料',
    addresses: '地址',
    save: '保存',
    saved: '已保存。',
    signOut: '退出',
    testNote: '测试账户。订单只存在这个浏览器会话里。',
    orderPaid: '测试已付',
  },
  search: {
    title: '搜索',
    placeholder: 'HOOP、手环…',
    submit: '搜索',
    empty: '没有匹配。试试 HOOP。',
    results: '结果',
  },
  notFound: {
    title: '没有这一页。',
    lede: '商店、手环和政策都在。',
    shop: '去商店',
    home: '首页',
  },
  pages: {
    back: '返回',
  },
};

const COPY: Record<ShopLocale, ShopCopy> = {en, zh};

export function shopCopy(locale: ShopLocale): ShopCopy {
  return COPY[locale];
}
