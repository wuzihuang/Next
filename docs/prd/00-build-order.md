# 00 · PRD 总目录 Build Order

> NEXTBODY HOOP · PRODUCT SPEC · BUILD ORDER
> 十二块规格板，一条从开机到设备的直线
> 这一页从左到右就是用户的时间轴，也是开发的顺序：先把人放进来（01–03），再把首屏立起来（04），
> 然后是问与答两条链路

| Stage | | Boards |
|---|---|---|
| **A · GET IN** | 先把人放进来 | 01 登录 · 02 Connect · 03 Onboarding |
| **B · THE SPINE** | 首屏立起来，再接上问与答 | 04 主页 · 07 AI 屏 · 05 Dock · 06 加号键 |
| **C · THE EVIDENCE** | 三张详情，每张只回答一句话 | 08 训练 · 09 燃料 · 10 成分 |
| **D · ME & DEVICE** | 最后才是设置，而且只许有一个二级页 | 11 我的 · 12 设备 |

**FOUNDATION · 本轮新增七块，读它们的顺序就是开工顺序**

> 前面 01–13 是屏，这七块是规矩。屏说长什么样，规矩说数字从哪来、名字叫什么、几点算一天、
> 哪句话不许说、哪个空缺不许填。

F0 裁决 · F1 导航 · F2 口径 · F3 数据与同步 · F4 服务端与 AI · F5 合规 · F6 交付 · F7 数据管线

**ARCHIVED** — 两块旧板已移入「归档」页.

## Artboard index

Node ids and sizes as `get_basic_info` reported them, so the next pass can fetch a board directly
instead of walking the canvas. Page `N-0` 「新版设计」 · 30 artboards · 30,258 nodes.

| Node | Board | Size |
|---|---|---|
| `1BUP-0` | 00 · PRD 总目录 Build Order | 1560 × 2654 |
| `QLX-0` | 01 · 登录注册 Sign In | 2174 × 2289 |
| `R3U-0` | 02 · Connect 手环配对 | 2174 × 2517 |
| `RHU-0` | 03 · Onboarding 建档与基线 | 2596 × 3718 |
| `T26-0` | 04 · 主页首屏 下屏双卡 | 2174 × 2736 |
| `10PM-0` | 05 · Dock 输入 打字/说话/照片 | 3440 × 5209 |
| `VYQ-0` | 06 · 加号键与手环测量 | 2596 × 6564 |
| `TPY-0` | 07 · AI 屏 MCP 渲染契约 | 1764 × 20003 |
| `URD-0` | 08 · 训练详情 Strain | 2174 × 3854 |
| `UY2-0` | 09 · 燃料详情 Fuel | 2174 × 3567 |
| `17P3-0` | 10 · 成分详情 Composition | 2174 × 5648 |
| `1EUA-0` | 10S · 称重录入 Add a weigh-in | 2174 × 2913 |
| `1ADA-0` | 11 · 我的 Profile | 2174 × 4132 |
| `1BEI-0` | 12 · 设备 Device | 2174 × 3498 |
| `1AD3-0` | 12S · 设备 · 二级弹窗 Device sheets | 1760 × 1174 |
| `1CC9-0` | 13 · 昨夜与 Body Battery | 2174 × 6538 |
| `SH5-0` | 01M · MOTION · 整页开机 First run | 4818 × 1561 |
| `8SV-0` | 02M · MOTION · Connect → Wordmark | 2174 × 1392 |
| `BV9-0` | 05M · MOTION · Dock 输入 键盘与语音 | 3524 × 3719 |
| `NSG-0` | 06M · MOTION · 加号键 吸附与测量 | 2656 × 5006 |
| `1BXH-0` | F0 · 裁决与全局改名 Rulings | 2174 × 4103 |
| `1C43-0` | F1 · 导航与信息架构 The Map | 2174 × 3308 |
| `1CW8-0` | F2 · 口径与公式 The Numbers | 2174 × 7147 |
| `1DBQ-0` | F3 · 数据与同步 Data & Sync | 2174 × 7572 |
| `1DOQ-0` | F4 · 服务端与 AI 契约 Server & AI | 2174 × 7176 |
| `1E1D-0` | F5 · 合规、权限与无障碍 Compliance | 2174 × 8140 |
| `1EEM-0` | F6 · 交付规则 Handoff | 2174 × 7742 |
| `1FAL-0` | F7 · 数据管线 The Pipeline | 2174 × 9393 |
| `1F2A-0` | 补屏 · 同意屏与 NO TARGET | 2174 × 4517 |
| `1F29-0` | APPICON | 513 × 632 |

⚠️ **F5 and F7 have no mirror in this folder and were never read.** F5 is 合规、权限与无障碍 —
permissions, consent and accessibility, 8140 points of it — and F7 is 数据管线. Every other
foundation board turned up defects when it was read against the running app; these two have not
been read at all. They are the first thing to fetch when Paper answers, ahead of the screen
boards.
