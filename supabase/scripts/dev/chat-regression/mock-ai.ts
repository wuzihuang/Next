export { generateObject } from "npm:ai@4.3.16";
export type { Tool } from "npm:ai@4.3.16";
export const state: { options?: any; mode: string } = {mode:"prose"};
export function streamText(options: any) {
  state.options = options;
  return {fullStream: (async function* () {
    if (state.mode === "text-tool") {
      const args = options.tools["screen.render.text"].parameters.parse({sub:"你好，这是完整回答。"});
      await options.tools["screen.render.text"].execute(args, {});
      return;
    }
    if (state.mode === "preamble") {
      yield {type:"text-delta",textDelta:"我先看看。"};
      yield {type:"step-finish",finishReason:"tool-calls"};
    }
    yield {type:"reasoning",textDelta:"private reasoning"};
    yield {type:"text-delta",textDelta:"12 加 13 等于 25。"};
    yield {type:"step-finish",finishReason:"stop"};
  })()};
}
