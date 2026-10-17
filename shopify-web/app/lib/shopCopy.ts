import type {ShopLocale} from './locale';

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
  checkout: {title: string; empty: string; errorEmail: string; address1: string; city: string; region: string; postal: string; country: string};
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
    lede: '$99 once for the band. Black or white. Both straps in the box. App AI is included.',
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
    codeHint: `Discounts are verified by Shopify at checkout.`,
    codeOk: 'Code saved for Shopify checkout.',
    codeBad: 'Code saved; Shopify will verify it at checkout.',
    qty: 'Qty',
  },
  checkout: {title: 'Checkout', empty: 'Add HOOP to the cart before checkout.', errorEmail: 'Enter a valid email address.', address1: 'Address', city: 'City', region: 'State', postal: 'Postal code', country: 'Country'},
  account: {
    title: 'Account',
    lede: 'Save contact preferences on this browser. This does not sign you into Shopify.',
    email: 'Email',
    name: 'Name',
    enter: 'Enter',
    welcome: 'Welcome',
    orders: 'Orders',
    noOrders: 'See your Shopify order confirmation for payment, shipping and order details.',
    profile: 'Profile',
    addresses: 'Address',
    save: 'Save',
    saved: 'Saved.',
    signOut: 'Sign out',
    testNote: 'Local contact preferences. Refer to Shopify for orders.',
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
    lede: '$99 一次付清买手环。黑色或白色。盒内两条表带都有。App 里的 AI 已包含。',
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
    codeHint: `优惠码会在 Shopify 结算时验证。`,
    codeOk: '优惠码已保存，结算时确认。',
    codeBad: '优惠码已保存，Shopify 将在结算时验证。',
    qty: '数量',
  },
  checkout: {title: '结算', empty: '请先将 HOOP 加入购物车。', errorEmail: '请输入有效邮箱。', address1: '地址', city: '城市', region: '省/州', postal: '邮编', country: '国家'},
  account: {
    title: '账户',
    lede: '在此浏览器保存联系方式设置。这不会登录 Shopify 账户。',
    email: '邮箱',
    name: '姓名',
    enter: '进入',
    welcome: '你好',
    orders: '订单',
    noOrders: '支付、配送和订单详情请查看 Shopify 订单确认页面。',
    profile: '资料',
    addresses: '地址',
    save: '保存',
    saved: '已保存。',
    signOut: '退出',
    testNote: '本地联系方式设置。真实订单请查看 Shopify 的订单确认页面。',
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
