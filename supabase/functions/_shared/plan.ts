// ADR 0018 · the plan. Title, summary, three to five tasks the model writes freely, saved
// one row per user day. Any surface may render one; the plan face is where it lives.
//
// The inputs are enumerable, so the plan surface does not walk the read phase: the server
// prefetches three user days and yesterday's ticks, the model renders in one step.

import { tool, type Tool } from "npm:ai@4.3.16";
import { z } from "npm:zod@3.25.76";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import type { Envelope } from "./contract.ts";
import type { NumberLedger } from "./ledger.ts";
import { addDays } from "./calendar.ts";

export const PLAN_RENDER = "plan.render";
export const PLAN_LOOKBACK_DAYS = 3;

/// ⚠️ Caps truncate, they do not reject. A hard max on a tool parameter makes the SDK
/// throw AI_InvalidToolArgumentsError and the whole turn dies over one long word (seen in
/// production on the first plan). The lengths are the writing rule; the trim is the safety net.
const trimmed = (max: number) => z.string().transform((s) => s.length > max ? s.slice(0, max) : s);
const slug = (s: string, i: number) => {
  const cleaned = s.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 24);
  return cleaned || `task-${i + 1}`;
};

export const PlanTask = z.object({
  id: trimmed(24).optional().describe("stable slug, e.g. bed-2230 / walk-30 / protein-lunch"),
  title: trimmed(14).describe("≤ 14 characters"),
  sub: trimmed(40).describe("≤ 40 characters, how to do it"),
  basis: trimmed(40).optional().describe("≤ 40 characters: the number or fact this task rests on; every number here must come from source_data or a tool return this turn. Do not put numbers in title or sub that are not in basis."),
});
export type PlanTask = z.infer<typeof PlanTask> & { id: string };

export const PlanArgs = z.object({
  title: trimmed(18).describe("≤ 18 characters"),
  summary: trimmed(120).describe("≤ 120 characters, one sentence on yesterday and today"),
  tasks: z.array(PlanTask).min(1).max(8).describe("three to five tasks"),
});

/// Everything the plan reads, fetched before the model runs. Failures are named, not
/// hidden: a missing night stays missing and the model says so.
export async function planContext(db: SupabaseClient, userId: string, dayKey: string) {
  const from = addDays(dayKey, -(PLAN_LOOKBACK_DAYS));
  const yesterday = addDays(dayKey, -1);
  const [results, nights, meals, plan, checks] = await Promise.all([
    db.from("daily_results")
      .select("user_day, training_load, reserve_score, fuel_balance_kcal, daily_direction, day_fuel(intake_state, kcal_in, kcal_out)")
      .eq("user_id", userId).gte("user_day", from).lte("user_day", dayKey).order("user_day"),
    db.from("night_score").select("user_day, score, duration_score, architecture_score, recovery_score, regularity_score")
      .eq("user_id", userId).gte("user_day", from).lte("user_day", dayKey).order("user_day"),
    db.from("meals").select("user_day, slot, kcal, protein_g").eq("user_id", userId).is("deleted_at", null)
      .gte("user_day", from).lte("user_day", dayKey).order("user_day"),
    db.from("daily_plans").select("user_day, title, summary, tasks").eq("user_id", userId).eq("user_day", yesterday).maybeSingle(),
    db.from("plan_task_checks").select("task_id, checked_at").eq("user_id", userId).eq("user_day", yesterday),
  ]);
  const failed = [
    ["daily_results", results.error], ["night_score", nights.error], ["meals", meals.error],
    ["daily_plans", plan.error], ["plan_task_checks", checks.error],
  ].filter(([, e]) => e).map(([n]) => n);
  const yesterdayPlan = plan.data
    ? {
      ...plan.data,
      tasks: (plan.data.tasks as PlanTask[]).map((t) => ({
        ...t, checked: (checks.data ?? []).some((c) => c.task_id === t.id),
      })),
    }
    : null;
  return {
    window: { from, to: dayKey, today: dayKey },
    days: results.data ?? [],
    nights: nights.data ?? [],
    meals: meals.data ?? [],
    yesterday_plan: yesterdayPlan,
    failed,
    instruction: "plan_context is prefetched evidence for today's plan: the last three user days and yesterday's plan with the user's own ticks. A ticked task is the user's claim; compare it with the data and say so without judging. Missing nights are missing, not zero.",
  };
}

export type PlanRow = {
  user_id: string; user_day: string; title: string; summary: string; tasks: PlanTask[];
  read_from: string; read_to: string; turn_id: string;
};

/// Written after the frame passes the audit, never before: a plan the audit throws away
/// must not be the plan the face reads back tomorrow.
export async function savePlanRow(db: SupabaseClient, row: PlanRow): Promise<boolean> {
  const { error } = await db.from("daily_plans").upsert(row, { onConflict: "user_id,user_day" });
  return !error;
}

export function buildPlanTool(
  db: SupabaseClient, userId: string, dayKey: string, turnId: string, ledger: NumberLedger,
  onRender: (env: Envelope, row: PlanRow) => void, locale: "zh-CN" | "en-US", window: { from: string; to: string },
): Record<string, Tool> {
  void db;
  const en = locale === "en-US";
  return {
    [PLAN_RENDER]: tool({
      description: en
        ? "Render today's plan: one title, one summary sentence, three to five tasks. Use for 'plan my day' or when the plan face asks. Saves the plan for the user day; it replaces an earlier plan for the same day."
        : "输出今天的计划：一句标题、一句总结、三到五条任务。用于「帮我排一下今天」或计划页的请求。按用户日保存，同一天再输出会覆盖。",
      parameters: PlanArgs,
      // deno-lint-ignore require-await
      execute: async (args): Promise<Record<string, unknown>> => {
        if (args.tasks.length < 3) return { rendered: false, error: "TOO_FEW_TASKS", say: "Give three to five tasks." };
        const ids = new Set<string>();
        const tasks: PlanTask[] = args.tasks.slice(0, 5).map((t, i) => {
          let id = slug(t.id || t.title, i);
          while (ids.has(id)) id = `${id.slice(0, 20)}-${i + 1}`;
          ids.add(id);
          return { ...t, id };
        });
        const row: PlanRow = {
          user_id: userId, user_day: dayKey, title: args.title, summary: args.summary, tasks,
          read_from: window.from, read_to: window.to, turn_id: turnId,
        };
        ledger.add(tasks.length, "plan.tasks.length");
        onRender({
          type: "plan", title: args.title, sentence: args.summary.slice(0, 48),
          footer: `${window.from} → ${window.to}`,
          data: { title: args.title, summary: args.summary, tasks, user_day: dayKey, read_from: window.from, read_to: window.to },
          ttl_min: 60, priority: "normal", locale, target: "plan",
        }, row);
        return { rendered: true, type: "plan", tasks: tasks.length };
      },
    }),
  };
}

export function planPrompt(locale: string): string {
  return locale.startsWith("zh")
    ? `PLAN
用户要今天的计划。证据已经在 source_data.plan_context 里：过去三天的负荷、睡眠分、电量、餐，以及昨天的计划和用户打的勾。先用一句总结说昨天做到了什么、数据是否印证（勾了早睡但夜间数据显示很晚，就照实说，不评判）；再给今天三到五条任务，每条一个短标题、一句怎么做、一句依据。没有夜就不排关于夜的任务，也不编分数。用 plan.render 输出，一轮一次。这里允许建议，但不用感叹号、不表扬。
数字规矩：屏上每一个数字都必须原样出现在 source_data 里。不许加总（几餐的蛋白不相加）、不许换算单位（432 分钟就写 432 分钟，不写 7 小时 12 分）、不许自己算差值和百分比。想说的数字如果 source_data 里没有，就不说。日期写成 09-05 这种两位形式。`
    : `PLAN
The user wants today's plan. The evidence is already in source_data.plan_context: the last three days of load, sleep score, battery and meals, plus yesterday's plan with the user's ticks. First one summary sentence on what yesterday delivered and whether the data agrees (a ticked early bedtime against a late night is stated plainly, not judged); then three to five tasks for today, each a short title, one line of how, one line of basis. No night, no night task and no invented score. Output with plan.render, once per turn. Advice is allowed here; exclamation marks and praise are not.
Number rule: every number on screen must appear verbatim in source_data. No sums (do not add up protein across meals), no unit conversions (432 minutes stays 432 minutes, never 7h12), no differences or percentages of your own. If a number is not in source_data, do not say it. Write dates as 09-05.`;
}
