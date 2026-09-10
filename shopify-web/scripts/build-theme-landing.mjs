// Snapshots the Hydrogen landing page into the Liquid theme templates.
//
//   npm run dev                                   # in another shell
//   node scripts/build-theme-landing.mjs [--base http://localhost:3000] [--check]
//
// The Liquid theme serves a static copy of the same landing page, so the two
// storefronts stay one design. This rewrites the Hydrogen routes into the
// theme's own query-string routes and the /landing assets into asset_url tags.
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const theme = resolve(here, '../../shopify-theme');
const args = process.argv.slice(2);
const check = args.includes('--check');
const baseIndex = args.indexOf('--base');
const base = baseIndex === -1 ? 'http://localhost:3000' : args[baseIndex + 1];

const TARGETS = [
  {route: '/', file: `${theme}/templates/index.liquid`, lang: 'en'},
  {route: '/zh', file: `${theme}/templates/page.zh.liquid`, lang: 'zh'},
];

function shopLink(path, query, lang) {
  const parts = [];
  if (query) parts.push(query);
  if (lang === 'zh') parts.push('lang=zh');
  return parts.length ? `${path}?${parts.join('&amp;')}` : path;
}

function toTheme(html, lang) {
  return (
    html
      // assets live in the theme's asset folder
      .replace(/\/(?:landing|band)\/([\w.-]+)/g, "{{ '$1' | asset_url }}")
      // the theme has no router: every shop surface is a query on the catalog
      .replace(/href="\/policies\/([\w-]+)"/g, (_, h) => `href="${shopLink('/collections/all', `page=${h}`, lang)}"`)
      .replace(/href="\/pages\/([\w-]+)"/g, (_, h) => `href="${shopLink('/collections/all', `page=${h}`, lang)}"`)
      .replace(/href="\/products\/([\w-]+)"/g, (_, h) => `href="${shopLink('/collections/all', `product=${h}`, lang)}"`)
      .replace(/href="\/collections\/all"/g, `href="${shopLink('/collections/all', '', lang)}"`)
      .replace(/href="\/blogs[\w/-]*"/g, `href="${shopLink('/collections/all', '', lang)}"`)
      .replace(/href="\/zh"/g, 'href="/pages/zh"')
  );
}

function extract(html) {
  const start = html.indexOf('<div class="lp" ');
  if (start === -1) throw new Error('landing root not found — is the dev server running?');
  const end = html.indexOf('<script nonce=', start);
  if (end === -1) throw new Error('end of landing root not found');
  return html.slice(start, end).trim();
}

let drift = false;
for (const target of TARGETS) {
  const response = await fetch(`${base}${target.route}`);
  if (!response.ok) throw new Error(`${target.route}: ${response.status}`);
  const next = `${toTheme(extract(await response.text()), target.lang)}\n`;
  const current = readFileSync(target.file, 'utf8');
  if (check) {
    if (next !== current) {
      drift = true;
      console.error(`${target.file} is out of date.`);
    }
  } else {
    writeFileSync(target.file, next);
    console.log(`${target.file}: ${next.length} bytes`);
  }
}

// The theme's stylesheet is the same file with liquid asset tags.
const css = readFileSync(resolve(here, '../app/styles/landing.css'), 'utf8').replace(
  /\/(?:landing|band)\/([\w.-]+)/g,
  "{{ '$1' | asset_url }}",
);
const cssFile = `${theme}/assets/landing.css.liquid`;
if (check) {
  if (css !== readFileSync(cssFile, 'utf8')) {
    drift = true;
    console.error(`${cssFile} is out of date.`);
  }
  if (drift) {
    console.error('Run: npm run build:theme-landing');
    process.exit(1);
  }
  console.log('The Liquid theme matches the Hydrogen landing.');
} else {
  writeFileSync(cssFile, css);
  console.log(`${cssFile}: ${css.length} bytes`);
}
