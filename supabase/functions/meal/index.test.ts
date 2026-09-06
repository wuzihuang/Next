import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleMeal } from "./index.ts";

Deno.test("retired meal endpoint directs every request to the unified workflow", async () => {
  const response = handleMeal(
    new Request("http://localhost/meal", {
      method: "POST",
      body: JSON.stringify({ text: "rice" }),
    }),
  );
  assertEquals(response.status, 410);
  assertEquals(await response.json(), {
    error: "WORKFLOW_REQUIRED",
    endpoint: "turn",
  });
});

Deno.test("retired meal endpoint still answers CORS preflight", () => {
  assertEquals(
    handleMeal(new Request("http://localhost/meal", { method: "OPTIONS" }))
      .status,
    200,
  );
});
