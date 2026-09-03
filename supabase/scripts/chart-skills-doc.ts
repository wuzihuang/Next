// docs/prd/07-chart-skills.md is generated from the registry, so the document and the
// prompt cannot drift apart:
//   deno run --config supabase/functions/deno.json supabase/scripts/chart-skills-doc.ts > docs/prd/07-chart-skills.md

import { CHART_SKILLS, chartChoicePrompt } from "../functions/_shared/skills.ts";
import { SOURCES } from "../functions/_shared/sources.ts";

const out: string[] = [];
out.push("# 07 · 图表 Skills — 云端 AI 什么时候用哪张图");
out.push("");
out.push("> 由 `supabase/functions/_shared/skills.ts` 生成，不要手改。每一条 Skill 同时是：一个 `screen.render.<type>` 工具的 description、系统提示词 S11 的一行、以及这份文档的一节。");
out.push("");
out.push("## 路由 · S11 原文");
out.push("");
out.push("```");
out.push(chartChoicePrompt());
out.push("```");
out.push("");
out.push("## 23 种图，各自的 Skill");
out.push("");
out.push("| type | 形状 | 用在 | 不用在 | 数据源 | 文案 | 落点 |");
out.push("|---|---|---|---|---|---|---|");
for (const s of CHART_SKILLS) {
  const src = s.sources.length ? s.sources.map((x) => `\`${x}\``).join("<br>") : "模型自己填字";
  out.push(`| \`${s.type}\` | ${s.shape} | ${s.use} | ${s.avoid} | ${src} | ${s.copy} | ${s.target} |`);
}
out.push("");
out.push("## 数据源目录 · series.get 与 screen.render.* 共用");
out.push("");
out.push("序列由服务端按数据源从库里读、分桶、成形；模型只选源，不抄点。空的源返回 null，工具答 NO_DATA，模型换图或用 text 写 ——。");
out.push("");
out.push("| source | 形状 | 内容 |");
out.push("|---|---|---|");
for (const s of SOURCES) out.push(`| \`${s.id}\` | ${s.kind} | ${s.says} |`);
out.push("");
out.push("## 不提供的四种");
out.push("");
out.push("- `wave` · ECG 走纸：库里没有心电采样，07 的规则是「能力表里没有的数据永远不给 widget」，所以不暴露给模型。");
out.push("- `hypnogram` `split` `o2night` · 睡眠三件：F0 规则 03，睡眠不上屏，夜晚只以它产出的 BODY BATTERY 出现。");
out.push("");
console.log(out.join("\n"));
