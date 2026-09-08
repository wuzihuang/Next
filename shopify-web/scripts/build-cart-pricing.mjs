import {readFile, writeFile} from 'node:fs/promises';
import ts from 'typescript';

const source = new URL('../app/lib/cartPricing.js', import.meta.url);
const destination = new URL('../../shopify-theme/assets/cart-pricing.js', import.meta.url);
const {outputText} = ts.transpileModule(await readFile(source, 'utf8'), {
  fileName: 'cartPricing.js',
  compilerOptions: {allowJs: true, target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS},
});
const output = '// Generated from shopify-web/app/lib/cartPricing.js. Run npm run build:shop-core.\n' +
  '(function () {\nconst exports = {};\n' + outputText + '\nwindow.NextBodyCart = exports;\n})();\n';

if (process.argv.includes('--check')) {
  const existing = await readFile(destination, 'utf8').catch(() => '');
  if (existing !== output) {
    throw new Error('Theme cart pricing is stale. Run npm run build:shop-core in shopify-web.');
  }
} else {
  await writeFile(destination, output);
}
