import type {ShopLocale} from './locale';
import {pickLocale} from './locale';
import {
  cartQuantity,
  cartSubtotal,
  cartTotal,
  discountAmount,
  shippingAmount,
  type CartState,
} from './shopMath';

export type Localized = {en: string; zh: string};

export type CatalogOptionValue = {
  id: string;
  label: Localized;
};

export type CatalogOption = {
  id: string;
  name: Localized;
  values: CatalogOptionValue[];
};

export type CatalogVariant = {
  id: string;
  options: Record<string, string>;
  image: string;
  images: string[];
  available: boolean;
};

export type CatalogProduct = {
  handle: string;
  collection: string;
  price: number;
  title: Localized;
  kicker: Localized;
  lede: Localized;
  description: {en: string[]; zh: string[]};
  facts: Array<{value: Localized; label: Localized}>;
  options: CatalogOption[];
  variants: CatalogVariant[];
};

export type CatalogCollection = {
  handle: string;
  title: Localized;
  lede: Localized;
  image: string;
};

export const COLLECTIONS: CatalogCollection[] = [
  {
    handle: 'all',
    title: {en: 'Shop', zh: '商店'},
    lede: {
      en: 'The band, and the straps that stay on it.',
      zh: '手环，以及一直戴在手上的表带。',
    },
    image: '/landing/buckle.png',
  },
  {
    handle: 'band',
    title: {en: 'The Band', zh: '手环'},
    lede: {
      en: 'HOOP. $99 once. Black or white. Knit or sport.',
      zh: 'HOOP。$99 一次付清。黑色或白色。编织或运动表带。',
    },
    image: '/band/product-black-nylon.jpg',
  },
  {
    handle: 'straps',
    title: {en: 'Straps', zh: '表带'},
    lede: {
      en: 'A second strap so the band never has to come off to dry.',
      zh: '多一条表带，手环就不用为了晾干而摘下来。',
    },
    image: '/band/product-sport-profile.jpg',
  },
];

export const PRODUCTS: CatalogProduct[] = [
  {
    handle: 'hoop',
    collection: 'band',
    price: 99,
    title: {en: 'HOOP', zh: 'HOOP'},
    kicker: {en: 'THE SCREENLESS BAND', zh: '无屏手环'},
    lede: {
      en: 'A band with no screen. It reads your heart, sleep, and training all day, and says it plainly in the NextBody app. $99. No subscription.',
      zh: '一条没有屏幕的手环。它整天读你的心率、睡眠和训练，然后在 NextBody App 里把话说清楚。$99，永不订阅。',
    },
    description: {
      en: [
        'A brushed steel frame around a woven loop. No glass, no glow. The band is the whole design.',
        'One side key. Knit nylon or a sport strap. Black or white. Eight millimeters on the wrist.',
        'Heart, HRV, stress, skin temperature, steps, and overnight oxygen. Body composition when you take a scan. The reading lives in the app — not on the band.',
      ],
      zh: [
        '拉丝钢框架，包住一圈编织表带。没有玻璃，没有发光。手环本身就是全部设计。',
        '一颗侧键。编织尼龙或运动表带。黑色或白色。手腕上只有八毫米。',
        '心率、HRV、压力、皮温、步数和夜间血氧。身体成分在你主动扫描时读取。读数在 App 里，不在手环上。',
      ],
    },
    facts: [
      {value: {en: '$99', zh: '$99'}, label: {en: 'ONCE', zh: '一次'}},
      {value: {en: '$0', zh: '$0'}, label: {en: 'PER MONTH', zh: '每月'}},
      {value: {en: '5 DAYS', zh: '5 天'}, label: {en: 'PER CHARGE', zh: '一次充电'}},
      {value: {en: '18+', zh: '18+'}, label: {en: 'NOT MEDICAL', zh: '非医疗器械'}},
    ],
    options: [
      {
        id: 'finish',
        name: {en: 'Finish', zh: '配色'},
        values: [
          {id: 'black', label: {en: 'Black', zh: '黑色'}},
          {id: 'white', label: {en: 'White', zh: '白色'}},
        ],
      },
      {
        id: 'strap',
        name: {en: 'Strap', zh: '表带'},
        values: [
          {id: 'knit', label: {en: 'Knit nylon', zh: '编织尼龙'}},
          {id: 'sport', label: {en: 'Sport', zh: '运动表带'}},
        ],
      },
    ],
    variants: [
      {
        id: 'hoop-black-knit',
        options: {finish: 'black', strap: 'knit'},
        image: '/band/product-black-nylon.jpg',
        images: [
          '/band/product-black-nylon.jpg',
          '/band/product-black-top.jpg',
          '/band/product-black-side.jpg',
          '/landing/buckle.png',
          '/landing/weave.png',
          '/landing/sensor.png',
        ],
        available: true,
      },
      {
        id: 'hoop-white-knit',
        options: {finish: 'white', strap: 'knit'},
        image: '/band/product-silver-nylon.jpg',
        images: [
          '/band/product-silver-nylon.jpg',
          '/landing/finishes.png',
          '/landing/light.png',
          '/landing/buckle.png',
          '/landing/weave.png',
        ],
        available: true,
      },
      {
        id: 'hoop-black-sport',
        options: {finish: 'black', strap: 'sport'},
        image: '/band/product-sport-profile.jpg',
        images: [
          '/band/product-sport-profile.jpg',
          '/landing/water.png',
          '/band/lifestyle-run.jpg',
          '/landing/sensor.png',
          '/band/product-black-side.jpg',
        ],
        available: true,
      },
      {
        id: 'hoop-white-sport',
        options: {finish: 'white', strap: 'sport'},
        image: '/landing/finishes.png',
        images: [
          '/landing/finishes.png',
          '/band/product-silver-nylon.jpg',
          '/landing/water.png',
          '/landing/light.png',
          '/landing/chase.png',
        ],
        available: true,
      },
    ],
  },
  {
    handle: 'knit-strap',
    collection: 'straps',
    price: 19,
    title: {en: 'Knit nylon strap', zh: '编织尼龙表带'},
    kicker: {en: 'STAY ON', zh: '一直戴着'},
    lede: {
      en: 'Woven, breathable, made to stay on. A second strap so HOOP does not have to come off.',
      zh: '编织、透气、为一直戴着而做。多一条，HOOP 就不用摘下来。',
    },
    description: {
      en: [
        'The everyday strap. Soft enough to sleep in. Open enough to dry on the wrist.',
        'Fits the HOOP case. Swap it in a few seconds — no tools.',
      ],
      zh: [
        '日常表带。软到可以戴着睡。透到戴在手上也能干。',
        '卡进 HOOP 表壳。几秒换好，不用工具。',
      ],
    },
    facts: [
      {value: {en: '$19', zh: '$19'}, label: {en: 'ONCE', zh: '一次'}},
      {value: {en: 'KNIT', zh: '编织'}, label: {en: 'NYLON', zh: '尼龙'}},
    ],
    options: [
      {
        id: 'color',
        name: {en: 'Color', zh: '颜色'},
        values: [
          {id: 'black', label: {en: 'Black', zh: '黑色'}},
          {id: 'white', label: {en: 'White', zh: '白色'}},
        ],
      },
    ],
    variants: [
      {
        id: 'knit-black',
        options: {color: 'black'},
        image: '/band/product-black-nylon.jpg',
        images: [
          '/band/product-black-nylon.jpg',
          '/landing/weave.png',
          '/band/lifestyle-fit.jpg',
        ],
        available: true,
      },
      {
        id: 'knit-white',
        options: {color: 'white'},
        image: '/band/product-silver-nylon.jpg',
        images: [
          '/band/product-silver-nylon.jpg',
          '/landing/finishes.png',
          '/landing/light.png',
        ],
        available: true,
      },
    ],
  },
  {
    handle: 'sport-strap',
    collection: 'straps',
    price: 19,
    title: {en: 'Sport strap', zh: '运动表带'},
    kicker: {en: 'WET WORK', zh: '下水也能戴'},
    lede: {
      en: 'Honeycomb elastomer for swim, shower, and heat. Keep the band on.',
      zh: '蜂窝弹性体，游泳、洗澡、出汗都能戴。手环不用摘。',
    },
    description: {
      en: [
        'A slim sport strap for days that get wet. It dries fast and holds the case low on the wrist.',
        'Same latch as the knit strap. Swap when you want a second finish on the same HOOP.',
      ],
      zh: [
        '给会湿的日子用的细运动表带。干得快，把表壳压在手腕上。',
        '和编织表带同一个卡扣。同一条 HOOP，想换外观就换。',
      ],
    },
    facts: [
      {value: {en: '$19', zh: '$19'}, label: {en: 'ONCE', zh: '一次'}},
      {value: {en: 'SPORT', zh: '运动'}, label: {en: 'ELASTOMER', zh: '弹性体'}},
    ],
    options: [
      {
        id: 'color',
        name: {en: 'Color', zh: '颜色'},
        values: [
          {id: 'black', label: {en: 'Black', zh: '黑色'}},
          {id: 'white', label: {en: 'White', zh: '白色'}},
        ],
      },
    ],
    variants: [
      {
        id: 'sport-black',
        options: {color: 'black'},
        image: '/band/product-sport-profile.jpg',
        images: [
          '/band/product-sport-profile.jpg',
          '/landing/water.png',
          '/band/lifestyle-run.jpg',
        ],
        available: true,
      },
      {
        id: 'sport-white',
        options: {color: 'white'},
        image: '/landing/water.png',
        images: [
          '/landing/water.png',
          '/landing/finishes.png',
          '/band/lifestyle-train.jpg',
        ],
        available: true,
      },
    ],
  },
];

export function getProduct(handle: string): CatalogProduct | undefined {
  return PRODUCTS.find((product) => product.handle === handle);
}

export function getCollection(
  handle: string,
): CatalogCollection | undefined {
  return COLLECTIONS.find((collection) => collection.handle === handle);
}

export function productsForCollection(handle: string): CatalogProduct[] {
  if (handle === 'all') return PRODUCTS;
  return PRODUCTS.filter((product) => product.collection === handle);
}

export function getVariant(
  variantId: string,
): {product: CatalogProduct; variant: CatalogVariant} | undefined {
  for (const product of PRODUCTS) {
    const variant = product.variants.find((item) => item.id === variantId);
    if (variant) return {product, variant};
  }
  return undefined;
}

export function variantTitle(
  product: CatalogProduct,
  variant: CatalogVariant,
  locale: ShopLocale,
): string {
  return product.options
    .map((option) => {
      const valueId = variant.options[option.id];
      const value = option.values.find((item) => item.id === valueId);
      return value ? pickLocale(locale, value.label.en, value.label.zh) : '';
    })
    .filter(Boolean)
    .join(' · ');
}

export function findVariant(
  product: CatalogProduct,
  selected: Record<string, string>,
): CatalogVariant | undefined {
  return product.variants.find((variant) =>
    product.options.every((option) => variant.options[option.id] === selected[option.id]),
  );
}

export function defaultSelection(product: CatalogProduct): Record<string, string> {
  return Object.fromEntries(
    product.options.map((option) => [option.id, option.values[0].id]),
  );
}

export function searchCatalog(term: string): CatalogProduct[] {
  const q = term.trim().toLowerCase();
  if (!q) return PRODUCTS;
  return PRODUCTS.filter((product) => {
    const hay = [
      product.handle,
      product.title.en,
      product.title.zh,
      product.kicker.en,
      product.kicker.zh,
      product.lede.en,
      product.lede.zh,
      ...product.description.en,
      ...product.description.zh,
    ]
      .join(' ')
      .toLowerCase();
    return hay.includes(q);
  });
}

export type HydratedLine = {
  variantId: string;
  quantity: number;
  price: number;
  productHandle: string;
  productTitle: Localized;
  variantLabel: Localized;
  image: string;
  available: boolean;
};

export function hydrateCart(cart: CartState): HydratedLine[] {
  return cart.lines.flatMap((line) => {
    const found = getVariant(line.variantId);
    if (!found) return [];
    return [
      {
        variantId: line.variantId,
        quantity: line.quantity,
        price: found.product.price,
        productHandle: found.product.handle,
        productTitle: found.product.title,
        variantLabel: {
          en: variantTitle(found.product, found.variant, 'en'),
          zh: variantTitle(found.product, found.variant, 'zh'),
        },
        image: found.variant.image,
        available: found.variant.available,
      },
    ];
  });
}

export type CartTotals = {
  quantity: number;
  subtotal: number;
  discount: number;
  shipping: number;
  total: number;
};

export function totalsForCart(cart: CartState): CartTotals {
  const lines = hydrateCart(cart);
  const subtotal = cartSubtotal(lines);
  const discount = discountAmount(subtotal, cart.discountCode);
  const shipping = shippingAmount(subtotal - discount, subtotal);
  return {
    quantity: cartQuantity(lines),
    subtotal,
    discount,
    shipping,
    total: cartTotal(subtotal, discount, shipping),
  };
}

export function relatedProducts(handle: string): CatalogProduct[] {
  return PRODUCTS.filter((product) => product.handle !== handle);
}
