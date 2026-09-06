import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  estimateMeal,
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
