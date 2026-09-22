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

// Native Shopify Pages render legal and support text without a JavaScript route.
// Publish each Page with the matching handle and templateSuffix in Shopify Admin.
const nativePages = [
  {
    handle: 'app-privacy',
    page: POLICIES.find((p) => p.handle === 'privacy-policy'),
  },
  {
    handle: 'app-terms',
    page: POLICIES.find((p) => p.handle === 'user-agreement'),
  },
  {
    handle: 'app-support',
    page: SITE_PAGES.find((p) => p.handle === 'app-support'),
  },
];
const escapeHTML = (value) =>
  value.replace(
    /[&<>"']/g,
    (char) =>
      ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;',
      })[char],
  );
const paragraphHTML = (value) =>
  escapeHTML(value)
    .replace(/(shop|privacy)@nextbody\.ai/g, '<a href="mailto:$&">$&</a>')
    .replace(
      /reportaproblem\.apple\.com/g,
      '<a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>',
    );
for (const {handle, page} of nativePages) {
  if (!page) throw new Error(`Missing source for ${handle}`);
  const markup = `{% doc %}
  Public NextBody app information, generated from the storefront policy and support sources.
{% enddoc %}
<style>
.nb-document{max-width:780px;margin:0 auto;padding:48px 24px 80px;color:#efefef;font:16px/1.75 system-ui,sans-serif;overflow-wrap:anywhere}
.nb-document a{color:#b4e7ca;text-decoration:underline;text-underline-offset:3px}
.nb-document nav{display:flex;flex-wrap:wrap;gap:12px 24px;margin-bottom:40px}
.nb-document h1{font-size:36px;line-height:1.2;margin:24px 0}
.nb-document h2{font-size:22px;line-height:1.4;margin:36px 0 12px}
.nb-document article+article{border-top:1px solid #444;margin-top:64px;padding-top:32px}
.nb-document p{margin:0 0 16px}
</style>
<main class="nb-document">
<nav aria-label="NextBody app information"><a href="{{ routes.root_url }}">NextBody</a><a href="{{ routes.all_products_collection_url }}?view=app-privacy">Privacy / 隐私</a><a href="{{ routes.all_products_collection_url }}?view=app-terms">Terms / 条款</a><a href="{{ routes.all_products_collection_url }}?view=app-support">Support / 支持</a><a href="#english">English</a><a href="#chinese">中文</a></nav>
${['en', 'zh']
  .map(
    (
      locale,
    ) => `<article lang="${locale === 'zh' ? 'zh-Hans' : 'en'}" id="${locale === 'zh' ? 'chinese' : 'english'}">
<${locale === 'en' ? 'h1' : 'h2'}>${escapeHTML(page.title[locale])}</${locale === 'en' ? 'h1' : 'h2'}>
<p>${escapeHTML(page.lede[locale])}</p>
${page.updated ? `<p>${locale === 'zh' ? '最后更新' : 'Last updated'}: ${escapeHTML(page.updated)}</p>` : ''}
${page.sections.map((section) => `<section><h2>${escapeHTML(section.heading[locale])}</h2>\n${section.body[locale].map((p) => `<p>${paragraphHTML(p)}</p>`).join('\n')}</section>`).join('\n')}
</article>`,
  )
  .join('\n')}
</main>
`;
  const files = [
    {name: `snippets/${handle}.liquid`, content: markup},
    ...['page', 'collection'].map((type) => ({
      name: `templates/${type}.${handle}.liquid`,
      content: `{% render '${handle}' %}\n`,
    })),
  ];
  for (const {name, content} of files) {
    const path = resolve(here, `../../shopify-theme/${name}`);
    if (check) {
      if (readFileSync(path, 'utf8') !== content)
        throw new Error(
          `${name} is out of date. Run npm run build:theme-pages`,
        );
    } else {
      writeFileSync(path, content);
    }
  }
}
console.log('Native app privacy, terms and support templates are current.');
