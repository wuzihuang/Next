import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { aiDisabled } from "./ai-switch.ts";

Deno.test("AI endpoints are closed unless AI_ENABLED=1", async () => {
  const before = Deno.env.get("AI_ENABLED");
  try {
    Deno.env.delete("AI_ENABLED");
    const closed = aiDisabled(new Request("http://local/turn", { method: "POST" }));
    assertEquals(closed?.status, 410);
    assertEquals(await closed?.json(), { error: "AI_DISABLED" });
    assertEquals(aiDisabled(new Request("http://local/turn", { method: "OPTIONS" }))?.status, 200);

    Deno.env.set("AI_ENABLED", "1");
    assertEquals(aiDisabled(new Request("http://local/turn", { method: "POST" })), null);
  } finally {
    if (before === undefined) Deno.env.delete("AI_ENABLED");
    else Deno.env.set("AI_ENABLED", before);
  }
});
