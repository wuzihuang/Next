import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  estimateMeal,
  foodDraftEnvelope,
  type MealEstimateDependencies,
} from "./meal-estimate.ts";

const nutrition = {
  name: "Rice",
  kcal: 200,
  protein_g: 4,
  carb_g: 40,
  fat_g: 1,
  confidence: "MEDIUM",
};

Deno.test("meal estimates use supplied model accounting and identical text/photo drafts", async () => {
  for (const image of [undefined, "data:image/jpeg;base64,YQ=="]) {
    const recorded: unknown[] = [];
    const abort = new AbortController();
    const deps: MealEstimateDependencies = {
      modelId: "qwen3.8-flash",
      generateObject: ((
        options: {
          abortSignal: AbortSignal;
          messages: { content: { type: string }[] }[];
        },
      ) => {
        assertEquals(options.abortSignal, abort.signal);
        assertEquals(
          options.messages[0].content.map((part) => part.type),
          image ? ["image", "text"] : ["text"],
        );
        return Promise.resolve({
          object: nutrition,
          usage: { promptTokens: 100, completionTokens: 20 },
          providerMetadata: { dashscope: { cachedPromptTokens: 60 } },
        });
      }) as unknown as MealEstimateDependencies["generateObject"],
      recordUsage: (usage, modelId) => {
        recorded.push({ usage, modelId });
        return Promise.resolve();
      },
    };
    const draft = await estimateMeal({
      text: "rice",
      image,
      locale: "en-US",
      draftId: "draft",
      abortSignal: abort.signal,
    }, deps);
    assertEquals(draft, {
      ...nutrition,
      draft_id: "draft",
      source: image ? "photo" : "typed",
      is_estimate: true,
      requires_confirmation: true,
      model_version: "qwen3.8-flash/2026-09",
    });
    assertEquals(recorded, [{
      usage: { promptTokens: 40, cachedTokens: 60, completionTokens: 20 },
      modelId: "qwen3.8-flash",
    }]);
  }
});

Deno.test("meal tool rejects empty input and remote images before model invocation", async () => {
  const deps: MealEstimateDependencies = {
    modelId: "qwen3.8-flash",
    generateObject: () => {
      throw new Error("must not run");
    },
    recordUsage: () => Promise.resolve(),
  };
  await assertRejects(
    () => estimateMeal({ text: " ", locale: "en" }, deps),
    Error,
    "MEAL_INPUT_REQUIRED",
  );
  await assertRejects(
    () =>
      estimateMeal({
        text: "rice",
        image: "https://example.com/meal.jpg",
        locale: "en",
      }, deps),
    Error,
    "INVALID_MEAL_IMAGE",
  );
});

Deno.test("a failed Grok meal generation falls back and attributes the draft to Qwen", async () => {
  const ids: string[] = [];
  const recorded: string[] = [];
  const draft = await estimateMeal({ text: "Rice", locale: "en-US" }, {
    generateObject: ((options: { model: { modelId: string } }) => {
      ids.push(options.model.modelId);
      if (ids.length === 1) return Promise.reject(Object.assign(new Error("invalid JSON"), { name: "AI_NoObjectGeneratedError" }));
      return Promise.resolve({ object: nutrition, usage: { promptTokens: 100, completionTokens: 20 } });
    }) as unknown as MealEstimateDependencies["generateObject"],
    recordUsage: (_usage, id) => { recorded.push(id); return Promise.resolve(); },
  });
  assertEquals(ids, ["grok-4.6", "qwen3.8-flash"]);
  assertEquals(recorded, ["qwen3.8-flash"]);
  assertEquals(draft.model_version, "qwen3.8-flash/2026-09");
  assertEquals(draft.requires_confirmation, true);
});

Deno.test("a finished estimate is already a confirmation card", () => {
  const draft = {
    ...nutrition,
    confidence: "MEDIUM" as const,
    draft_id: "draft",
    source: "typed" as const,
    is_estimate: true as const,
    requires_confirmation: true as const,
    model_version: "qwen3.8-flash/2026-09",
  };
  const zh = foodDraftEnvelope(draft, "zh-CN");
  assertEquals(zh.type, "food");
  assertEquals(zh.target, "fuel");
  assertEquals(zh.action, "确认记录");
  assertEquals(zh.data.name, "Rice");
  assertEquals(zh.data.kcal, 200);
  const en = foodDraftEnvelope(draft, "en-US");
  assertEquals(en.action, "CONFIRM");
  assertEquals(en.sentence, "Review this meal estimate before saving.");
});
