export {cors, json, userDayKey} from "../../../functions/_shared/db.ts";
export const tables: string[] = [];
export async function currentUserId() {return "test-user";}
export function userClient() {return {from(table: string) {
  tables.push(table);
  const result = {data:table === "consents" ? {choice:"granted"} : table === "profiles" ? {locale:"zh-CN",timezone:"UTC"} : table === "screen_frames" ? {id:"frame"} : null, count:0,error:null};
  const chain:any = new Proxy({}, {get(_, key) {if(key === "then") return Promise.resolve(result).then.bind(Promise.resolve(result)); return () => chain;}});
  return chain;
}};}
