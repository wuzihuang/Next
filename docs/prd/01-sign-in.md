# 01 · 登录注册 Sign In

Mirrored from the Paper board while the server was answering.

> AUTH SPEC · SIGN IN & SIGN UP
> 不设密码，就没有忘记
> 登录只做一件事：把这条手环和一个人绑起来。Apple、Google、或者一个邮箱加六位数——三条路都在 15 秒内落地。

**NOT IN V1** — 手机号 + 短信验证码（国内发行时再开）· 微信 / Strava / Garmin 第三方授权 ·
邮箱 + 密码作为兜底登录.

## 01 · 授权入口 Gate — `ENTRY · 0 INPUT`

> 冷启动第一屏。三个按钮顺序固定：**Apple 在最上且是唯一实心白**，Google 次之，邮箱兜底。
> 全屏不出现「注册」二字。

Three buttons, each 358 × 56, in a 390 × 188 block. Footer:
`By continuing you agree to our` ` Terms ` `and` ` Privacy Policy`.

## 02 · 邮箱 Email — `STEP 01 / 02`

Back chevron 44 × 44 + `STEP 01 / 02` on one 390 × 46 row. Title `Your email`;
sub `We'll send a 6-digit code.` / `No password to set.`; label `EMAIL ADDRESS`;
field 342 × 62; below, `Use Apple or Google instead`.

> 键盘随屏起，光标已落在输入框内。

## 03 · 验证码 Code — `STEP 02 / 02 · AUTO-SUBMIT`

Title `Enter the code`; six boxes 50 × 64; `Didn't get it?` `Resend in` `00:43`;
`Use a different email`.

> 六格自动聚焦、自动前进，支持整串粘贴与 iOS 系统自动填充。填满第六格立刻提交，不等用户点按钮。

## 04 · 品牌动画 Handoff — `2.6S · ONE SHOT · NEW ONLY`

Five beats: `01 FLASH · 0.00` · `02 RAIN · 0.35` · `03 STACK · 1.10` · `04 LOCK · 1.80` ·
`05 SETTLE · 2.15 → 2.60`.

> 验证通过的那一秒不弹 toast、不打对勾，也不落在任何页面上——直接进 MOTION SPEC · 01 的像素坠落。

## 05 · 分流 Branch — `IDENTITY · SERVER SIDE`

> 三条登录路径在服务端汇成同一个 identity。分流只看两个事实：这个标识见过没有，这个账号绑过手环没有。

| Branch | Lands on | Why |
|---|---|---|
| NEW | → Connect · 01 Turn it on | 标识首次出现。账号当场建好；品牌动画只在这条路上播。 |
| RETURNING | → 主页 | 有账号且手环在册。不播品牌动画，跳过全部 onboarding。 |
| UNPAIRED | → Connect · 01（档案保留） | 只补配对这一步，身高体重目标一律不再问。 |
| MERGE | → 并入原账号 | 同一邮箱换了登录方式。绝不新建第二个。 |

## Edge cases — `出错的时候，不清屏`

> 共同的规则只有一条：已经输进去的邮箱和数字，任何错误都不许清空。

1. **WRONG CODE** — 六格整体转红描边，横向抖 6px，一次错误 haptic，然后清空回到第一格。第 5 次错误锁定这个邮箱 15 分钟。
2. **EXPIRED** — 验证码 10 分钟过期。不报红：主按钮原地换成 `Get a new code`。
3. **RATE LIMITED** — 同一邮箱一小时最多 5 封。第 6 次不发信，也不解释原因。
4. **NO NETWORK** — 按钮原地转成加载态，8 秒超时后变回可点。不弹系统弹窗、不退回上一屏。
5. **APPLE / GOOGLE** — 在系统弹窗上取消的，静默回到 01，一个提示都不给——取消不是错误。

## 验证码与会话 · 硬规则

1. 六位数字，10 分钟有效，一次性。发出新码的同一刻旧码作废。
2. 60 秒内不允许重发。重发上限 5 次 / 小时 / 邮箱。
3. 连续 5 次错码锁定该邮箱 15 分钟——锁在服务端。
4. 会话 90 天滑动续期。在新设备登录不踢掉旧设备——手环跟账号走，不跟手机走。
5. 不做密码、不做用户名、不做找回流程。邮箱本身就是找回方式。
6. 登录阶段一个健康字段都不读。HealthKit 授权发生在 Onboard · 01。
7. 品牌动画只在 NEW 分支播一次，与首次启动、配对成功共用同一份实现。

## 上线前必须成立

- Sign in with Apple 必须在场且排第一（Guideline 4.8）。
- 删除账号入口必须在 App 内可达：我的 · 设备 → 危险区。
- 三条路径产出的账号在服务端不可区分。数据结构里不留 provider 特权字段。
- 埋点六个：`AUTH_GATE_VIEW` · `AUTH_METHOD_TAP{APPLE|GOOGLE|EMAIL}` · `AUTH_*`
- 验收线：Gate 到主页 / Connect 的 P50 ≤ 15 秒，邮箱路径完成率 ≥ 85%。
