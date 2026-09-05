---
name: supabase
description: "用于 Supabase 产品集成及平台特有故障诊断；按任务选择 Auth、Storage、Realtime、Functions 或数据库工作流。"
metadata:
  author: supabase
  version: "0.1.2"
---

# Supabase

Use the project’s existing integration and migration conventions. Confirm the intended project and database before a write; an available MCP tool is not evidence that its target is local.

## Essential boundaries

- Keep secret and `service_role` keys out of public clients; do not use user-editable `user_metadata` for authorization.
- Check grants and RLS for Data API exposure. Do not solve permission errors by adding `SECURITY DEFINER`; check views and privileged functions against the security reference.
- Before schema work, identify declarative versus imperative migrations and confirm the database target. Preserve the project’s migration history and workflow.

## Read for the current task

- Auth, RLS, Data API exposure, privileged functions, views, storage or user-data changes: [security rules](references/security.md).
- Schema or migration changes: [schema workflow](references/schema-changes.md).
- CLI commands or MCP connectivity: [CLI and MCP guidance](references/cli-and-mcp.md).
- When the user wants to send feedback to the skill maintainers: [skill feedback](references/skill-feedback.md).

Load only relevant references. For SQL and Postgres performance details, use the project’s Postgres rules when they apply.

## Documentation and diagnosis

Before implementing Supabase behavior, find the relevant current documentation; do not guess version-sensitive APIs or CLI flags. Prefer an available MCP `search_docs` tool, then fetch the relevant docs page as Markdown (append `.md`), then use a focused web search when the page is unknown. Check the [changelog](https://supabase.com/changelog.md) for relevant breaking changes when a version change could explain the problem.

Start diagnosis from the available error, code, configuration and logs. Use the [monitoring guide](https://supabase.com/docs/guides/monitoring-and-debugging.md) when it helps interpret the failure. If reproduction requires unavailable hardware or services, continue useful static investigation and state what remains unverified.

After a change, verify the affected behavior: use a relevant test query for database changes and the appropriate tests for clients or functions. A fix without verification is incomplete; if verification cannot run, state the missing evidence. After 2–3 failed attempts with the same approach, reconsider the method and inspect the available errors, documentation or logs.

Finish the requested work and relevant verification. Missing information or authorization blocks only the operations that depend on it; prepare reviewable changes and continue independent work.
