import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";

/** One account and calendar for a formal read, shared with its chart projection. */
export interface ReadContext {
  db: SupabaseClient;
  userId: string;
  dayKey: string;
  tz: string;
  from?: string;
  to?: string;
}
