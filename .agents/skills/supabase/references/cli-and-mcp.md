# Supabase CLI, MCP and documentation

Read when working with CLI commands or troubleshooting MCP connectivity.

## Supabase CLI

Use the installed CLI’s `--help` when command or flag support is uncertain. Check the installed version before relying on version-specific behavior.

```bash
supabase --help                    # All top-level commands
supabase <group> --help            # Subcommands (e.g., supabase db --help)
supabase <group> <command> --help  # Flags for a specific command
```

**Supabase CLI Known gotchas:**

- `supabase db query` requires **CLI v2.79.0+** → use MCP `execute_sql` or `psql` as fallback
- `supabase db advisors` requires **CLI v2.81.3+** → use MCP `get_advisors` as fallback
- In imperative migration projects, create new hand-authored migration files with `supabase migration new <name>` first. Never invent a migration filename or rely on memory for the expected format. Declarative schema projects generate migrations from `supabase/schemas/`.

**Version check and upgrade:** Run `supabase --version` to check. For CLI changelogs and version-specific features, consult the [CLI documentation](https://supabase.com/docs/reference/cli/introduction) or [GitHub releases](https://github.com/supabase/cli/releases).

## Supabase MCP Server

For setup instructions, server URL, and configuration, see the [MCP setup guide](https://supabase.com/docs/guides/getting-started/mcp).

**Troubleshooting connection issues** — use the checks relevant to the observed failure:

1. **Check if the server is reachable:**
   `curl -so /dev/null -w "%{http_code}" https://mcp.supabase.com/mcp`
   A `401` is expected (no token) and means the server is up. Timeout or "connection refused" means it may be down.

2. **Check the active harness configuration:**
   Inspect the configuration actually used by this host (for example Codex configuration or a project `.mcp.json`). Verify the intended server and project. Do not create a second configuration or switch servers merely because `.mcp.json` is absent.

3. **Authenticate the MCP server:**
   If the intended server is reachable and the active harness configuration is correct but tools are not visible, check whether authentication is missing. The Supabase MCP server uses OAuth 2.1 — tell the user to trigger the auth flow in their agent, complete it in the browser, and reload the session.
