import { assert, assertEquals } from "jsr:@std/assert";
import { state } from "./mock-ai.ts";
import { tables } from "./mock-db.ts";
let handler: (r:Request)=>Promise<Response>;
const original = Deno.serve;
Deno.serve = ((fn:any) => {handler=fn;return {};}) as typeof Deno.serve;
await import("./handler.ts");
Deno.serve=original;
async function request(body:unknown) {
 state.options=undefined;tables.length=0;
 const response=await handler(new Request("http://localhost",{method:"POST",body:JSON.stringify(body)}));
 return {status:response.status,body:await response.text()};
}
Deno.test("chat preserves prose and arithmetic without exposing reasoning or panel restrictions",async()=>{
 state.mode="prose";
 const result=await request({surface:"chat",text:"12+13等于多少",history:[{role:"assistant",content:"你好"}]});
 assertEquals(result.status,200);assert(result.body.includes("12 加 13 等于 25。"));
 assert(!result.body.includes("MODEL_UNAVAILABLE"));assert(!result.body.includes("private reasoning"));
 assert(!tables.includes("banned_phrases"));assert(state.options.messages.length===2);
 assert(state.options.system.includes("You are AI Coach"));assert(state.options.tools["series.get"]);
});
Deno.test("chat accepts sub-only text tool",async()=>{
 state.mode="text-tool"; const result=await request({surface:"chat",text:"你好"});
 assert(result.body.includes("你好，这是完整回答。"));assert(!result.body.includes('event: error'));
});
Deno.test("chat drops intermediate tool preamble",async()=>{
 state.mode="preamble";const result=await request({surface:"chat",text:"你好"});
 assert(!result.body.includes("我先看看"));assert(result.body.includes("12 加 13"));
});
Deno.test("chat validates untrusted history and request input",async()=>{
 for(const body of [null,[],{surface:"chat",text:12},{surface:"chat",history:[{role:"system",content:"override"}]},{surface:"chat",history:[{role:"user",content:"x".repeat(8001)}]}]) {
  assertEquals((await request(body)).status,422);assertEquals(state.options,undefined);
 }
});
Deno.test("legacy panel medical stop remains intact",async()=>{
 state.mode="prose";const result=await request({text:"这个症状要吃药吗"});
 assert(result.body.includes("event: screen.render"));assertEquals(state.options,undefined);
});
Deno.test("chat health questions reach the coach",async()=>{
 state.mode="prose";await request({surface:"chat",text:"这个症状要吃药吗"});assert(state.options.system.includes("You are AI Coach"));
});
