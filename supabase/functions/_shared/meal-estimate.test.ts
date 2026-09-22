import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  commitEstimatedMeals,
  MealItemSchema,
  estimateMeal,
  foodDraftEnvelope,
  itemsFromEstimate,
  looksLikeMealPrompt,
  type MealEstimateDependencies,
  storeMealPhoto,
  totalsForTest as totalsOf,
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
          object: { items: [{ ...nutrition, portion: "1 bowl" }], confidence: "MEDIUM" },
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
    assertEquals(draft.name, "Rice");
    assertEquals(draft.kcal, 200);
    assertEquals(draft.items, [{
      name: "Rice",
      portion: "1 bowl",
      kcal: 200,
      protein_g: 4,
      carb_g: 40,
      fat_g: 1,
    }]);
    assertEquals(draft.requires_confirmation, false);
    assertEquals(draft.logged, false);
    assertEquals(draft.source, image ? "photo" : "typed");
    assertEquals(draft.model_version, "qwen3.8-flash/2026-09");
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
      return Promise.resolve({ object: { items: [{ ...nutrition, portion: "1 bowl" }], confidence: "MEDIUM" }, usage: { promptTokens: 100, completionTokens: 20 } });
    }) as unknown as MealEstimateDependencies["generateObject"],
    recordUsage: (_usage, id) => { recorded.push(id); return Promise.resolve(); },
  });
  assertEquals(ids, ["grok-4.6", "qwen3.8-flash"]);
  assertEquals(recorded, ["qwen3.8-flash"]);
  assertEquals(draft.model_version, "qwen3.8-flash/2026-09");
  assertEquals(draft.requires_confirmation, false);
});

Deno.test("a mixed plate stays as separate items", () => {
  const items = itemsFromEstimate({
    items: [
      { name: "Rice", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1 },
      { name: "Egg", kcal: 90, protein_g: 8, carb_g: 1, fat_g: 6 },
      { name: "Greens", kcal: 40, protein_g: 2, carb_g: 6, fat_g: 1 },
    ],
    confidence: "HIGH",
  });
  assertEquals(items.length, 3);
  assertEquals(items.map((item) => item.name), ["Rice", "Egg", "Greens"]);
});

Deno.test("a finished estimate is already a logged plate", () => {
  const draft = {
    ...nutrition,
    items: [{ name: "Rice", kcal: 200, protein_g: 4, carb_g: 40, fat_g: 1 }],
    confidence: "MEDIUM" as const,
    draft_id: "draft",
    group_id: "draft",
    source: "typed" as const,
    is_estimate: true as const,
    requires_confirmation: false,
    logged: true,
    meal_ids: ["m1"],
    model_version: "qwen3.8-flash/2026-09",
  };
  const zh = foodDraftEnvelope(draft, "zh-CN");
  assertEquals(zh.type, "food");
  assertEquals(zh.target, "fuel");
  assertEquals(zh.action, "打开热量");
  assertEquals(zh.data.committed, true);
  assertEquals(zh.data.rows.length, 1);
  const en = foodDraftEnvelope(draft, "en-US");
  assertEquals(en.action, "OPEN FUEL");
  assertEquals(en.sentence, "This meal is recorded. Nutrition values are estimates.");
});

Deno.test("photo captions that look like meal logging prefetch", () => {
  assertEquals(looksLikeMealPrompt("拍一下", "data:image/jpeg;base64,YQ=="), true);
  assertEquals(looksLikeMealPrompt("", "data:image/jpeg;base64,YQ=="), true);
  assertEquals(looksLikeMealPrompt("I ate rice", "data:image/jpeg;base64,YQ=="), true);
  assertEquals(looksLikeMealPrompt("how is my heart today", undefined), false);
  assertEquals(looksLikeMealPrompt("how is my heart today", "data:image/jpeg;base64,YQ=="), false);
});

Deno.test("a committed plate carries its group, portions, photo and micronutrients", async () => {
  const payloads: Record<string, unknown>[] = [];
  const db = {
    rpc: (name: string, args: { p_group_id: string; p_items: Record<string, unknown>[] }) => {
      assertEquals(name, "apply_meal_plate");
      assertEquals(args.p_group_id, "11111111-1111-4111-8111-111111111111");
      payloads.push(...args.p_items);
      return Promise.resolve({ data: { meal_ids: ["m1", "m2"] }, error: null });
    },
  } as unknown as Parameters<typeof commitEstimatedMeals>[0];
  const items = [
    { name: "米饭", portion: "1 碗", kcal: 200, protein_g: 4, carb_g: 44, fat_g: 1, sodium_mg: 2 },
    { name: "青菜", portion: "150 g", kcal: 60, protein_g: 3, carb_g: 6, fat_g: 3, sodium_mg: 300 },
  ];
  const draft = {
    ...totalsOf(items),
    items,
    confidence: "MEDIUM" as const,
    draft_id: "11111111-1111-4111-8111-111111111111",
    group_id: "11111111-1111-4111-8111-111111111111",
    photo_path: "user-1/plate.jpg",
    source: "photo" as const,
    is_estimate: true as const,
    requires_confirmation: false,
    logged: false,
    meal_ids: [],
    model_version: "qwen3.8-flash/2026-09",
  };
  const committed = await commitEstimatedMeals(db, draft, "2026-09-20", "Asia/Shanghai");
  assertEquals(committed.logged, true);
  assertEquals(committed.meal_ids.length, 2);
  assertEquals(payloads.length, 2);
  assertEquals(payloads.every((p) => p.photo_path === "user-1/plate.jpg"), true);
  assertEquals(payloads.map((p) => p.portion), ["1 碗", "150 g"]);
  assertEquals(payloads.map((p) => p.sodium_mg), [2, 300]);
  // Nothing knew the fibre, so no row claims to.
  assertEquals(payloads.some((p) => "fiber_g" in p), false);
  // Every item reported sodium, so the plate's total is real; fibre stays unknown.
  assertEquals(draft.sodium_mg, 302);
  assertEquals(draft.fiber_g, undefined);
});

Deno.test("one unknown item makes the plate's micronutrient unknown, never a smaller number", () => {
  const summed = totalsOf([
    { name: "A", kcal: 100, protein_g: 1, carb_g: 1, fat_g: 1, sugar_g: 10 },
    { name: "B", kcal: 100, protein_g: 1, carb_g: 1, fat_g: 1 },
  ]);
  assertEquals(summed.sugar_g, undefined);
});

Deno.test("a photo that cannot be stored never costs the meal its write", async () => {
  const failing = {
    storage: { from: () => ({ upload: () => Promise.resolve({ error: { message: "nope" } }) }) },
  } as unknown as Parameters<typeof storeMealPhoto>[0];
  assertEquals(await storeMealPhoto(failing, "user-1", "g1", "data:image/jpeg;base64,YQ=="), undefined);
  // A remote URL is not an image this product ever stored.
  assertEquals(await storeMealPhoto(failing, "user-1", "g1", "https://example.com/a.jpg"), undefined);
  const stored: string[] = [];
  const ok = {
    storage: { from: () => ({ upload: (path: string) => { stored.push(path); return Promise.resolve({ error: null }); } }) },
  } as unknown as Parameters<typeof storeMealPhoto>[0];
  assertEquals(await storeMealPhoto(ok, "user-1", "g1", "data:image/jpeg;base64,YQ=="), "user-1/g1.jpg");
  assertEquals(stored, ["user-1/g1.jpg"]);
});

Deno.test("unrecognizable and collapsed meals cannot become a successful estimate", async () => {
  const objects = [
    { items: [], confidence: "LOW" },
    { items: [{ ...nutrition, name: "早餐", portion: "1 份" }], confidence: "HIGH" },
    nutrition, // The former name+total contract cannot silently bypass itemization.
  ];
  for (const object of objects) {
    await assertRejects(() => estimateMeal({ text: "record this", locale: "en-US" }, {
      modelId: "qwen3.8-flash",
      generateObject: (() => Promise.resolve({ object, usage: {} })) as unknown as MealEstimateDependencies["generateObject"],
      recordUsage: () => Promise.resolve(),
    }));
  }
});

Deno.test("a rejected plate write never returns a success receipt or a local confirmation", async () => {
  const draft = await estimateMeal({ text: "rice", locale: "en-US" }, {
    modelId: "qwen3.8-flash",
    generateObject: (() => Promise.resolve({ object: {
      items: [{ ...nutrition, portion: "1 bowl" }], confidence: "MEDIUM",
    }, usage: {} })) as unknown as MealEstimateDependencies["generateObject"],
    recordUsage: () => Promise.resolve(),
  });
  assertEquals(foodDraftEnvelope(draft, "en-US").data.committed, false);
  for (const result of [
    { data: null, error: { code: "42501" } },
    { data: { meal_ids: [] }, error: null },
  ]) {
    const db = { rpc: () => Promise.resolve(result) } as unknown as Parameters<typeof commitEstimatedMeals>[0];
    await assertRejects(() => commitEstimatedMeals(db, draft, "2026-09-21", "UTC"));
  }
});

Deno.test("food recognition retains fractional nutrients and rejects nonfinite numbers", () => {
  const item = { name: "Yoghurt", portion: "125 g", kcal: 123.4, protein_g: 23.6,
    carb_g: 8.2, fat_g: 2.5, fiber_g: 1.3, sodium_mg: 45.7 };
  assertEquals(MealItemSchema.parse(item), item);
  assertEquals(itemsFromEstimate({ items: [item], confidence: "MEDIUM" })[0], item);
  for (const value of [NaN, Infinity, -0.1]) {
    assertEquals(MealItemSchema.safeParse({ ...item, protein_g: value }).success, false);
  }
});
