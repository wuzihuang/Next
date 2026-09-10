// Generates the Liquid theme's PAGES array from the Hydrogen sources so the two
// storefronts never drift on legal or content copy.
//
//   node --experimental-strip-types scripts/build-theme-pages.mjs [--check]
//
// The theme is a static snapshot: shopify-theme/assets/shop.js holds the same
// pages as ../app/lib/policies.ts and ../app/lib/sitePages.ts, in the theme's
// own {handle, kicker, title, lede, sections} shape.
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

import {POLICIES} from '../app/lib/policies.ts';
import {SITE_PAGES} from '../app/lib/sitePages.ts';

const here = dirname(fileURLToPath(import.meta.url));
const target = resolve(here, '../../shopify-theme/assets/shop.js');
const check = process.argv.includes('--check');

const LEGAL = {en: 'LEGAL', zh: '法律'};

const pages = [
  ...POLICIES.map((policy) => ({
    handle: policy.handle,
    kicker: LEGAL,
    title: policy.title,
    lede: {
      en: `${policy.lede.en} Updated ${policy.updated}.`,
      zh: `${policy.lede.zh} 更新于 ${policy.updated}。`,
    },
    sections: policy.sections,
  })),
  ...SITE_PAGES.map((page) => ({
    handle: page.handle,
    kicker: page.kicker,
    title: page.title,
    lede: page.lede,
    sections: page.sections,
  })),
];

const body = JSON.stringify(pages, null, 2)
  .split('\n')
  .map((line, i) => (i === 0 ? line : `${line}`))
  .join('\n');

const block = `const PAGES = ${body};`;

const source = readFileSync(target, 'utf8');
const start = source.indexOf('const PAGES = [');
if (start === -1) throw new Error('shop.js: PAGES array not found');
const end = source.indexOf('\n];', start);
if (end === -1) throw new Error('shop.js: end of PAGES array not found');
const next = source.slice(0, start) + block + source.slice(end + 3);

if (check) {
  if (next !== source) {
    console.error('shop.js is out of date. Run: npm run build:theme-pages');
    process.exit(1);
  }
  console.log('shop.js pages match the Hydrogen sources.');
} else {
  writeFileSync(target, next);
  console.log(`shop.js: wrote ${pages.length} pages`);
}
