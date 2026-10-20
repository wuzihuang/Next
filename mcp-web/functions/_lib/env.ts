export interface McpEnv {
  SUPABASE_URL?: string;
  SUPABASE_PUBLISHABLE_KEY?: string;
  MCP_PUBLIC_ORIGIN?: string;
}

export type FetchLike = (input: Request | URL | string, init?: RequestInit) => Promise<Response>;

export function configuredOrigin(value: string | undefined): string | null {
  const trimmed = value?.trim();
  if (!trimmed) return null;
  try {
    return new URL(trimmed).origin;
  } catch {
    return null;
  }
}

export function resolvePublicOrigin(request: Request, env: McpEnv): string {
  return configuredOrigin(env.MCP_PUBLIC_ORIGIN) ?? new URL(request.url).origin;
}
