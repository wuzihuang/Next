# NextBody MCP

Cloudflare Pages site for `https://mcp.nextbody.ai`. ChatGPT, Claude, Cursor, and Grok connect here to a person's own NextBody data. Supabase Auth's OAuth 2.1 server is the authorization server. This package does not implement the `mcp` Edge Function or `record_mcp_grant`; those live in the Supabase project.

## Routing

Pages Functions under `functions/.well-known/` are real routes. Wrangler 4.151.1 walks that directory (`forEachFile` does not skip names that start with a dot). Checked with `wrangler pages dev public` on 127.0.0.1:8791:

- `GET /.well-known/oauth-protected-resource`
- `GET /.well-known/oauth-protected-resource/mcp`
- `GET /.well-known/oauth-authorization-server` (proxied)
- `GET /.well-known/oauth-authorization-server/mcp` (proxied)

No `_worker.js`, catch-all, or `_routes.json`.

## Owner setup

1. Install, build, and deploy from this directory:

   ```bash
   pnpm install && SUPABASE_PUBLISHABLE_KEY=... pnpm build
   wrangler pages project create nextbody-mcp
   pnpm deploy
   ```

   Functions read `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` and `MCP_PUBLIC_ORIGIN` from
   `[vars]` in `wrangler.toml`. Because `pages_build_output_dir` is set, that file is the Pages
   configuration and variables set in the dashboard are ignored.

   `NODE_ENV=production pnpm build` refuses to run when the publishable key is missing. A non-production build writes a fake placeholder into `public/config.js` and prints a warning. Do not deploy that placeholder.

2. Custom domain: add `mcp.nextbody.ai` on the Pages project. At the DNS host for `nextbody.ai`, add CNAME `mcp` → `nextbody-mcp.pages.dev`. The zone can stay where it is.

3. Supabase dashboard:

   - Authentication → OAuth Server: enable it, set the authorization path to `/oauth/consent`, and enable dynamic client registration.
   - Authentication → URL Configuration: Site URL `https://mcp.nextbody.ai`. Add redirect URL `https://mcp.nextbody.ai/oauth/consent**`.

4. Apple and Google buttons stay hidden on the consent page until the build lists them:
   `SIGN_IN_PROVIDERS=apple,google pnpm build`. Email codes work without either.

   Apple web sign-in: create a Services ID under the same Apple team as the iOS app. Return URL: `https://gkgzwcxivnffsecshvfs.supabase.co/auth/v1/callback`. Add that Services ID to the Supabase Apple provider client IDs, next to the app bundle id. The same team keeps Hide My Email on one account.

5. Google: create a Web OAuth client. Authorized redirect URI is the same Supabase callback. Add its client id and secret to the Supabase Google provider, and keep the iOS client id in the allowed list.

6. Smoke test, after the Edge Function is deployed:

   ```bash
   curl -i https://mcp.nextbody.ai/mcp -X POST \
     -H 'content-type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
   ```

   Expect 401 and `www-authenticate: Bearer resource_metadata="https://mcp.nextbody.ai/.well-known/oauth-protected-resource"`. Then connect Cursor, Claude, or ChatGPT with `https://mcp.nextbody.ai/mcp`.

## Local dev

`pnpm dev` builds with a placeholder key (unless `SUPABASE_PUBLISHABLE_KEY` is set) and runs `wrangler pages dev public`.

Functions read `mcp-web/.dev.vars` (gitignored):

```
SUPABASE_URL=https://gkgzwcxivnffsecshvfs.supabase.co
SUPABASE_PUBLISHABLE_KEY=
MCP_PUBLIC_ORIGIN=https://mcp.nextbody.ai
```

Generated and ignored: `public/_headers` (CSP `connect-src` is the configured `SUPABASE_URL` origin), `public/config.js`, `public/landing.js`, `public/oauth/consent/app.js`, `public/fonts/`, `node_modules/`, `.wrangler/`.
