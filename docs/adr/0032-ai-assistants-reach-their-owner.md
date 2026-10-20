# 外部 AI 助手经 MCP 只读取它主人的数据

2026-10-18 用户裁决。每个 NextBody 用户可以把 ChatGPT、Claude、Cursor、Grok 等支持远程 MCP 的
客户端连到**自己的**数据上，读指标、睡眠、餐食，并在单独授权后把口述的食物记成餐。这与 App 内
AI（ADR 0018 / 0030，`AIFeature.enabled = false`）无关：不调用任何模型，不碰 `AI/` 两个目录。

## 决定

1. **地址里不带密钥。** 用户复制的只有 `https://mcp.nextbody.ai/mcp`。客户端第一次请求得到
   `401` + `WWW-Authenticate: Bearer resource_metadata=…`（RFC 9728），随后走 Supabase Auth 的
   OAuth 2.1 服务器（动态注册 + PKCE）。用户在 `mcp.nextbody.ai/oauth/consent` 用同一个账号登录、
   同意。没有个人 API Key 可复制、可泄露、可轮换。
2. **令牌就是 Supabase JWT，多一个 `client_id` claim。** RLS 照常按 `auth.uid()` 隔离，所以助手
   永远只看到主人自己的行。为了不让它拿着这张令牌去打 App 的全部接口：
   - PostgREST 预请求钩子 `public.mcp_request_gate()`：令牌无 `client_id` 直接放行（App 不受影响）；
     有 `client_id` 时必须存在未撤销的 `mcp_grants` 行，并且只允许 8 张只读表的 GET 与少数 RPC，
     写餐 RPC 还要 `can_write`。其余一律 `MCP_PATH_NOT_ALLOWED`。白名单表的外键嵌入面由 SQL 测试锁住。
   - Edge Functions 的 `currentUserId` 拒绝带 `client_id` 的令牌；只有 `mcp` 函数用 `assistantCaller`。
   - Storage 上一条 restrictive policy 拒绝所有 OAuth 令牌。
3. **两份记录组成一次连接。** Supabase Auth 的 grant 持有 refresh token；我们的 `mcp_grants` 记录
   `can_write`、`last_used_at`、`revoked_at`，是网关每次请求都查的那一份。同意页先 `record_mcp_grant`
   再 `approveAuthorization`。App 断开时**先删 Auth grant，再 `revoke_mcp_grant`**——反过来会留下一个
   跳过同意页、随后又被网关拒绝的循环。撤销对下一次请求立即生效（`401 invalid_token`），不等令牌过期。
4. **写入默认关闭。** 同意页可以勾选「允许记餐」，App 里每个助手一个开关。`log_meal` 走与拍照估餐
   相同的 `apply_meal_plate`（同意检查、6 天窗口、幂等 `request_id`），`model_version = mcp:<客户端名>`，
   写完 `settle_now` 重算当日。`delete_meal` 只删 `apply_meal_operation` 允许删的行。
5. **预算。** `consume_request_budget` 新增 `mcp` 端点，每分钟 60 次 `tools/call`。
6. **托管。** 同意页、`.well-known` 元数据与 `/mcp` 反代放在 Cloudflare Pages 免费层
   （`mcp-web/`，子域名 CNAME，不迁移整个 zone）。`/mcp` 原样转发到 Supabase 的 `mcp` 函数，
   `verify_jwt = false`，鉴权在函数里做。

## 实现

- 迁移 `supabase/migrations/20261018100000_ai_assistants_reach_their_owner.sql`；pgTAP
  `supabase/tests/mcp_request_gate.sql`。
- Edge Function `supabase/functions/mcp/`（`server.ts` 协议、`tools.ts` 工具、`index.test.ts`）。
  工具：`list_metrics`、`read_metrics`、`get_day_summary`、`get_sleep_night`、`list_meals`、
  `log_meal`、`delete_meal`。无状态 Streamable HTTP（JSON 响应），协议 2024-11-05 至 2025-11-25。
- `supabase/config.toml`：`[auth.oauth_server] enabled`、`allow_dynamic_registration`，
  本地 `site_url` 指向同意页开发端口。
- iOS：Profile › DATA & LEGAL › AI ASSISTANTS（`AssistantsSheet`）——复制地址、各客户端步骤、
  已连接列表（Auth grant ∪ `mcp_grants`）、记餐开关、断开。
- `mcp-web/`：Cloudflare Pages 项目，见其 README。

## 已知余险

- OAuth 令牌仍可调用 GoTrue 的 `/auth/v1/user` 一类端点（读邮箱、改资料）。Supabase 尚不支持自定义
  scope，也不能按 `client_id` 限制 GoTrue。
- `aud` 仍是 `authenticated`，没有受众绑定；靠 `client_id` 区分。
- 生产库若已有其他 `pgrst.db_pre_request` 配置，本迁移会覆盖它，部署前先查
  `select rolconfig from pg_roles where rolname = 'authenticator'`。
- 外部助手读到的数据会进入其服务商，App 文案已写明。

## 上线步骤

2026-10-18 已完成 1–3（同时推上了此前未上生产的 6 个餐食迁移，并按线上源码给非 AI 函数补上
`client_id` 拒绝，见 STATUS）。剩 4：网页上的 Apple / Google 登录，配好后用
`SIGN_IN_PROVIDERS=apple,google` 重新构建同意页。

1. `supabase db push` 应用迁移；`supabase functions deploy mcp --no-verify-jwt`；设置函数密钥
   `MCP_PUBLIC_ORIGIN=https://mcp.nextbody.ai`。
2. Supabase Dashboard › Authentication › OAuth Server：启用，打开 Dynamic client registration，
   授权路径填 `/oauth/consent`；URL Configuration 的 Site URL 填 `https://mcp.nextbody.ai`，
   Redirect URLs 加 `https://mcp.nextbody.ai/oauth/consent**`。
3. Cloudflare Pages 建项目指向 `mcp-web/`，按其 README 设置环境变量；在 nextbody.ai 的 DNS 加
   `mcp` CNAME 到 `<project>.pages.dev`，并在 Pages 里绑定自定义域名。
4. 同意页登录：Apple 需要同一 Team 下的 Services ID（Return URL 为 Supabase 回调），Google 需要
   Web 客户端 ID，均填进 Supabase Auth 的对应 provider；邮箱验证码无需额外配置。
5. 冒烟：Claude/ChatGPT 加连接器 → 同意 → `get_day_summary`；App 里打开记餐 → `log_meal`；断开 → 下一次调用 401。
