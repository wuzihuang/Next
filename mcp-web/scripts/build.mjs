import { copyFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as esbuild from "esbuild";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DEFAULT_SUPABASE_URL = "https://gkgzwcxivnffsecshvfs.supabase.co";
const PLACEHOLDER_KEY = "dev-only-placeholder-not-a-real-supabase-key";

const FONT_FILES = [
  ["@fontsource/inter-tight/files/inter-tight-latin-700-normal.woff2", "inter-tight-latin-700-normal.woff2"],
  ["@fontsource/inter-tight/files/inter-tight-latin-800-normal.woff2", "inter-tight-latin-800-normal.woff2"],
  ["@fontsource/jost/files/jost-latin-400-normal.woff2", "jost-latin-400-normal.woff2"],
  ["@fontsource/jost/files/jost-latin-500-normal.woff2", "jost-latin-500-normal.woff2"],
  ["@fontsource/doto/files/doto-latin-600-normal.woff2", "doto-latin-600-normal.woff2"],
  ["@fontsource/inter-tight/LICENSE", "LICENSE-inter-tight.txt"],
  ["@fontsource/jost/LICENSE", "LICENSE-jost.txt"],
  ["@fontsource/doto/LICENSE", "LICENSE-doto.txt"],
];

function allowPlaceholder() {
  return process.argv.includes("--dev") || process.env.NODE_ENV !== "production";
}

function publishableKey() {
  const fromEnv = process.env.SUPABASE_PUBLISHABLE_KEY?.trim();
  if (fromEnv) return fromEnv;
  if (allowPlaceholder()) {
    console.warn("SUPABASE_PUBLISHABLE_KEY is unset; writing a fake placeholder into public/config.js");
    return PLACEHOLDER_KEY;
  }
  console.error("SUPABASE_PUBLISHABLE_KEY is required for production builds");
  process.exit(1);
}

function supabaseUrl() {
  return process.env.SUPABASE_URL?.trim() || DEFAULT_SUPABASE_URL;
}

function writeConfig() {
  const config = {
    supabaseUrl: supabaseUrl(),
    supabaseKey: publishableKey(),
    providers: (process.env.SIGN_IN_PROVIDERS ?? "").split(",").map((p) => p.trim()).filter(Boolean),
  };
  const destination = resolve(root, "public/config.js");
  mkdirSync(dirname(destination), { recursive: true });
  writeFileSync(destination, `window.NEXTBODY_CONFIG = ${JSON.stringify(config)};\n`);
}

// The browser talks to exactly one Supabase project, so connect-src names that origin.
function writeHeaders() {
  const csp = [
    "default-src 'self'",
    "script-src 'self'",
    `connect-src 'self' ${new URL(supabaseUrl()).origin}`,
    "img-src 'self' data: https:",
    "style-src 'self' 'unsafe-inline'",
    "frame-ancestors 'none'",
    "base-uri 'none'",
    "form-action 'self'",
  ].join("; ");
  const rules = [
    "/*",
    `  Content-Security-Policy: ${csp}`,
    "  X-Frame-Options: DENY",
    "  Referrer-Policy: no-referrer",
    "  X-Content-Type-Options: nosniff",
    "",
  ];
  writeFileSync(resolve(root, "public/_headers"), rules.join("\n"));
}

function copyFonts() {
  const destinationDir = resolve(root, "public/fonts");
  mkdirSync(destinationDir, { recursive: true });
  for (const [from, to] of FONT_FILES) {
    copyFileSync(resolve(root, "node_modules", from), resolve(destinationDir, to));
  }
}

async function bundle(entry, outfile) {
  await esbuild.build({
    entryPoints: [resolve(root, entry)],
    bundle: true,
    format: "esm",
    platform: "browser",
    target: "es2022",
    outfile: resolve(root, outfile),
    legalComments: "none",
  });
}

async function main() {
  writeConfig();
  writeHeaders();
  copyFonts();
  await bundle("src/landing.ts", "public/landing.js");
  await bundle("src/consent.ts", "public/oauth/consent/app.js");
}

await main();
