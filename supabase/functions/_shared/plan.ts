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
import { addDays } from "./sources.ts";

export const PLAN_RENDER = "plan.render";
export const PLAN_LOOKBACK_DAYS = 3;

export const PlanTask = z.object({
  id: z.string().min(1).max(24).describe("stable slug, e.g. bed-2230 / walk-30 / protein-lunch"),
  title: z.string().min(1).max(14),
  sub: z.string().min(1).max(40),
  basis: z.string().max(40).optional().describe("the number or fact this task rests on; every number must come from source_data or a tool return this turn"),
});
export type PlanTask = z.infer<typeof PlanTask>;

export const PlanArgs = z.object({
  title: z.string().min(1).max(18),
  summary: z.string().min(1).max(120),
  tasks: z.array(PlanTask).min(3).max(5),
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

export function buildPlanTool(
  db: SupabaseClient, userId: string, dayKey: string, turnId: string, ledger: NumberLedger,
  onRender: (env: Envelope) => void, locale: "zh-CN" | "en-US", window: { from: string; to: string },
): Record<string, Tool> {
  const en = locale === "en-US";
  return {
    [PLAN_RENDER]: tool({
      description: en
        ? "Render today's plan: one title, one summary sentence, three to five tasks. Use for 'plan my day' or when the plan face asks. Saves the plan for the user day; it replaces an earlier plan for the same day."
        : "输出今天的计划：一句标题、一句总结、三到五条任务。用于「帮我排一下今天」或计划页的请求。按用户日保存，同一天再输出会覆盖。",
      parameters: PlanArgs,
      execute: async (args) => {
        const tasks = args.tasks.map((t, i) => ({ ...t, id: t.id || `task-${i + 1}` }));
        const ids = new Set<string>();
        for (const t of tasks) {
          if (ids.has(t.id)) return { rendered: false, error: "DUPLICATE_TASK_ID", say: "Give every task a distinct id." };
          ids.add(t.id);
        }
        const row = {
          user_id: userId, user_day: dayKey, title: args.title, summary: args.summary, tasks,
          read_from: window.from, read_to: window.to, turn_id: turnId,
        };
        const { error } = await db.from("daily_plans").upsert(row, { onConflict: "user_id,user_day" });
        if (error) return { rendered: false, error: "PLAN_SAVE_FAILED", say: "The plan could not be saved. Render text instead." };
        ledger.add(tasks.length, "plan.tasks.length");
        onRender({
          type: "plan", title: args.title, sentence: args.summary.slice(0, 48),
          footer: `${window.from} → ${window.to}`,
          data: { title: args.title, summary: args.summary, tasks, user_day: dayKey, read_from: window.from, read_to: window.to },
          ttl_min: 60, priority: "normal", locale, target: "plan",
        });
        return { rendered: true, type: "plan", tasks: tasks.length };
      },
    }),
  };
}

export function planPrompt(locale: string): string {
  return locale.startsWith("zh")
    ? `PLAN
用户要今天的计划。证据已经在 source_data.plan_context 里：过去三天的负荷、睡眠分、电量、餐，以及昨天的计划和用户打的勾。先用一句总结说昨天做到了什么、数据是否印证（勾了早睡但夜间数据显示很晚，就照实说，不评判）；再给今天三到五条任务，每条一个短标题、一句怎么做、一句依据。没有夜就不排关于夜的任务，也不编分数。用 plan.render 输出，一轮一次。这里允许建议，但不用感叹号、不表扬。`
    : `PLAN
The user wants today's plan. The evidence is already in source_data.plan_context: the last three days of load, sleep score, battery and meals, plus yesterday's plan with the user's ticks. First one summary sentence on what yesterday delivered and whether the data agrees (a ticked early bedtime against a late night is stated plainly, not judged); then three to five tasks for today, each a short title, one line of how, one line of basis. No night, no night task and no invented score. Output with plan.render, once per turn. Advice is allowed here; exclamation marks and praise are not.`;
}
