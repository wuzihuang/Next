import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createOpenAICompatible } from "npm:@ai-sdk/openai-compatible@0.2.14";
import { streamText } from "npm:ai@4.3.16";
import { ThoughtStream } from "./thoughts.ts";

for (const providerName of ["dashscope", "vercel-gateway"]) {
  Deno.test(`${providerName}: provider reasoning is emitted before completion`, async () => {
    const emitted: string[] = [];
    const thoughts = new ThoughtStream((text) => emitted.push(text));
    let finish!: () => void;
    const provider = createOpenAICompatible({
      name: providerName,
      baseURL: "https://example.invalid/v1",
      apiKey: "test-only",
      fetch: (_url, init) => {
        const body = JSON.parse(String((init as { body?: unknown })?.body));
        assertEquals(body.enable_thinking, true);
        assertEquals(body.thinking_budget, 200);
        const encoder = new TextEncoder();
        return new Response(
          new ReadableStream({
            start(controller) {
              const send = (
                delta: Record<string, string>,
                reason: string | null = null,
              ) => {
                controller.enqueue(encoder.encode(`data: ${
                  JSON.stringify({
                    id: "test",
                    object: "chat.completion.chunk",
                    created: 1,
                    model: "test",
                    choices: [{ index: 0, delta, finish_reason: reason }],
                  })
                }\n\n`));
              };
              send({ reasoning_content: "先查看昨夜睡眠。" });
              finish = () => {
                send({ content: "回答" });
                send({}, "stop");
                controller.enqueue(encoder.encode("data: [DONE]\n\n"));
                controller.close();
              };
            },
          }),
          { headers: { "content-type": "text/event-stream" } },
        );
      },
    });
    const result = streamText({
      model: provider("test"),
      prompt: "test",
      maxRetries: 0,
      providerOptions: {
        [providerName]: { enable_thinking: true, thinking_budget: 200 },
      },
    });
    let checkedLive = false;
    for await (const part of result.fullStream) {
      thoughts.accept(part);
      if (part.type === "reasoning") {
        assertEquals(emitted, ["先查看昨夜睡眠"]);
        checkedLive = true;
        finish();
      }
    }
    assertEquals(checkedLive, true);
    assertEquals(emitted, ["先查看昨夜睡眠"]);
  });
}
