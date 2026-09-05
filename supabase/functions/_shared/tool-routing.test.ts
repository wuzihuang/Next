import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { chartSkillsForScope } from "./skills.ts";

Deno.test("scoped chart tools retain only compatible renderers and safe fallbacks", () => {
  assertEquals(
    chartSkillsForScope(["sleep.stages", "sleep.mix"]).map((skill) => skill.type),
    ["metric", "text", "hypnogram", "split"],
  );
  assertEquals(
    chartSkillsForScope(["heart.today"]).map((skill) => skill.type),
    ["metric", "text", "line"],
  );
});
