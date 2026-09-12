# 问题反馈直接落成 GitHub issue，「导出我的数据」这一行撤掉

2026-09-12 用户裁决。「把『导出我的数据』删除了，新增一个反馈问题：进去后用户可以直接反馈问题，有标题和内容还有图片，直接反馈到我的 GitHub repo 的 issue 中。」

## 为什么撤掉导出

EXPORT MY DATA 那张 sheet 只做了决定过的一半：把账户里的东西数一遍、列出行数，页脚写着「发出去还不在这个版本——合规路径还没定」。一个既不能发也不能存的导出，对用户是一行永远走不通的入口，对代码是 `exportPreparing`、一个 DEBUG 钩子和四条文案。`export` Edge Function 本身留着（归档和账户删除的清理还用得着它的读法），只是个人页不再有它的行。隐私政策里「你可以在 个人 → 导出我的数据 导出全部」那句同步删掉，剩下的仍然成立。

## 决定

- **入口是 DATA & LEGAL 里的一行 REPORT A PROBLEM（反馈问题）**，站在导出原来的位置。sheet 里三样东西：标题（`FieldBox`）、描述（同一个 chip 长高成 `TextEditor`）、最多三张截图（`PhotosPicker`，缩略图右上角可删）。一个 Send。
- **只有一个去处：`wuzihuang/Next` 的 issue。** 手机把 `{title, body, images[{mime, base64}], context}` POST 给新的 `feedback` Edge Function；函数用 `GITHUB_FEEDBACK_TOKEN`（只对该仓库 Issues 读写的 fine-grained PAT）调 Issues API，打 `feedback` + `needs-triage` 两个标签，`needs-triage` 就是 `docs/agents/triage-labels.md` 里维护者待看的那个。手机永远拿不到 GitHub token。
- **截图走 `feedback-images` 公开桶。** Issues API 不收附件，只认 URL；函数用 service key 传到 `<user_id>/<时间戳>-<uuid>-<n>.jpg`，把公开 URL 以 `![screenshot n](…)` 写进 issue 正文。路径不可猜，桶只允许 jpeg/png、3 MiB。手机端 `FeedbackReport.Image` 压到 1280 px、≤ 600 KiB 一张——这不是喂模型，可以比 `AIImagePayload` 的 640 px 清楚得多。
- **正文里先是人写的话，再是机器知道的事。** 描述整段以引用块写入（用户打的 `#` 不会变成我们的标题），然后是截图，最后一张表：App 版本与 build、iOS、机型（`iPhone17,2` 这种 crash log 用的标识，不做营销名对照表）、语言、手环固件与连接状态、时区、user id、发送时刻。不带任何健康数据。
- **失败不清表单。** 服务器给出 issue 号之前，标题、描述、截图都在；断网、5xx、GitHub 拒绝各有一行文案。429（每分钟 5 条，`nb.consume_request_budget` 新加的 `feedback` 档）说等一会儿；503 `FEEDBACK_UNCONFIGURED` 说这台服务器还没配 token——那是部署问题，不是用户的。
- **`app.open {sheet: feedback}` 顶替 `export`。** `entities.ts` 的 SHEETS 列表与手机端 `PhoneTools` 同步改名；`NB_DEBUG_SHEET=feedback` 与 `NB_DEBUG_EDGE=feedback_filled` 走模拟器。

## 边界

- 没有 token 之前功能是死的：`supabase secrets set GITHUB_FEEDBACK_TOKEN=…`（可选 `GITHUB_FEEDBACK_REPO`，默认 `wuzihuang/Next`）是唯一的开关。
- 公开桶意味着知道 URL 的人都能看那张截图。截图是用户自己选的、发给一个私有仓库的，路径里有 uuid；如果以后 issue 要对外，先把桶改成签名 URL。
- 限流函数是**文本补丁**（`replace` 锚在 `when 'account-delete' then 6`），不是重写：它已经在四个迁移里定义过，抄任何一版都会把别的档位（`sleep-correction`）抹掉。
