import type {ShopLocale} from './locale';
import {pickLocale} from './locale';
import {quoteCart, resolveVariant, type CartState} from './cartPricing.js';

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
  includes: {en: string[]; zh: string[]};
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
    title: {en: 'HOOP', zh: 'HOOP'},
    lede: {
      en: '$99 once. Black or white. Both straps in the box.',
      zh: '$99 一次付清。黑色或白色。盒内两条表带都有。',
    },
    image: '/kit/hoop-black-a2.png',
  },
  {
    handle: 'band',
    title: {en: 'The Band', zh: '手环'},
    lede: {
      en: 'HOOP. $99 once. Pick black or white.',
      zh: 'HOOP。$99 一次付清。选黑色或白色。',
    },
    image: '/kit/hoop-black-a2.png',
  },
];

const HOOP_BLACK_IMAGES = [
  '/kit/hoop-black-a2.png',
  '/kit/hoop-black-f11.png',
  '/kit/hoop-black-c6.png',
  '/kit/hoop-black-a1.png',
  '/kit/hoop-black-e8.png',
  '/kit/hoop-black-b3.png',
];

const HOOP_WHITE_IMAGES = [
  '/kit/hoop-white-a1.png',
  '/kit/hoop-white-f13.png',
  '/kit/hoop-white-c7.png',
  '/kit/hoop-white-c9.png',
  '/kit/hoop-white-e7.png',
  '/kit/hoop-white-b5.png',
];

export const PRODUCTS: CatalogProduct[] = [
  {
    handle: 'hoop',
    collection: 'band',
    price: 99,
    title: {en: 'HOOP', zh: 'HOOP'},
    kicker: {en: 'THE BAND', zh: '手环'},
    lede: {
      en: 'No screen. The wrist stays quiet. NextBody reads the day. $99 once. Both straps in the box.',
      zh: '没有屏幕。手腕保持安静。NextBody 读这一天。$99 一次付清。盒内两条表带都有。',
    },
    description: {
      en: [
        'A brushed steel frame. No glass, no glow. The band is the whole design.',
        'Pick black or white. Knit nylon and the sport strap both ship in the box. Swap them — no tools.',
        'Heart, HRV, stress, skin temperature, steps, and overnight oxygen. Body composition when you take a scan. The reading lives in the app — not on the band.',
      ],
      zh: [
        '拉丝钢框架。没有玻璃，没有发光。手环本身就是全部设计。',
        '选黑色或白色。编织尼龙和运动表带都在盒里。换带不用工具。',
        '心率、HRV、压力、皮温、步数和夜间血氧。身体成分在你主动扫描时读取。读数在 App 里，不在手环上。',
      ],
    },
    includes: {
      en: ['HOOP', 'Knit nylon strap', 'Sport strap'],
      zh: ['HOOP 手环', '编织尼龙表带', '运动表带'],
    },
    facts: [
      {value: {en: '0', zh: '0'}, label: {en: 'PER MONTH', zh: '每月'}},
      {value: {en: '5', zh: '5'}, label: {en: 'DAYS / CHARGE', zh: '天 / 次充电'}},
      {value: {en: '18+', zh: '18+'}, label: {en: 'NOT MEDICAL', zh: '非医疗器械'}},
    ],
    options: [
      {
        id: 'finish',
        name: {en: 'Color', zh: '颜色'},
        values: [
          {id: 'black', label: {en: 'Black', zh: '黑色'}},
          {id: 'white', label: {en: 'White', zh: '白色'}},
        ],
      },
    ],
    variants: [
      {
        id: 'hoop-black',
        options: {finish: 'black'},
        image: HOOP_BLACK_IMAGES[0],
        images: HOOP_BLACK_IMAGES,
        available: true,
      },
      {
        id: 'hoop-white',
        options: {finish: 'white'},
        image: HOOP_WHITE_IMAGES[0],
        images: HOOP_WHITE_IMAGES,
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
  return resolveVariant(PRODUCTS, variantId);
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
  return quoteCart(cart, PRODUCTS).lines.map(({line, product, variant}) => ({
    variantId: line.variantId,
    quantity: line.quantity,
    price: product.price,
    productHandle: product.handle,
    productTitle: product.title,
    variantLabel: {
      en: variantTitle(product, variant, 'en'),
      zh: variantTitle(product, variant, 'zh'),
    },
    image: variant.image,
    available: variant.available,
  }));
}

export type CartTotals = {
  quantity: number;
  subtotal: number;
  discount: number;
  shipping: number;
  total: number;
};

export function totalsForCart(cart: CartState): CartTotals {
  const {lines: _lines, ...totals} = quoteCart(cart, PRODUCTS);
  return totals;
}

export function relatedProducts(handle: string): CatalogProduct[] {
  return PRODUCTS.filter((product) => product.handle !== handle);
}
