# Schema changes

Identify the intended project, database target, and existing migration workflow before making a schema change. A tool being available does not establish its target or authorize a write.

## Declarative schemas

When the project uses `supabase/schemas/` or configured `schema_paths`, edit the desired schema and generate a migration using that workflow. Do not start by hand-writing a migration. Review the resulting SQL before applying it. See the [declarative database schemas guide](https://supabase.com/docs/guides/local-development/declarative-database-schemas).

## Imperative migrations

Follow the repository’s established migration process. Use `supabase migration new <name>` for a new hand-authored migration when that CLI workflow is available.

Direct DDL iteration with `execute_sql` or CLI query is appropriate only after confirming the tool targets a disposable local database. Do not assume an MCP connection is local. Remote or shared databases use the project’s reviewed migration and deployment process within the user’s authorized scope.

### Local iteration and migration history

The original skill distinguishes exploratory SQL from applying a tracked migration. In a confirmed disposable local database, `execute_sql` or `supabase db query` can be used for exploratory schema changes without creating migration history entries. `apply_migration` records a migration entry; do not use it for every exploratory iteration when the intended next step is to derive a clean migration from a diff/pull. Already-recorded changes can affect what a later diff or pull produces.

For the original local pull workflow, the command examples are:

```bash
supabase db advisors
supabase db pull <descriptive-name> --local --yes
supabase migration list --local
```

Run the relevant advisors and review [security.md](security.md) before finalizing changes involving views, functions, triggers or storage. The original CLI notes specify v2.81.3+ for `db advisors`; an available MCP `get_advisors` is an alternative after confirming its target. Review and fix relevant findings before proceeding.

These examples belong to that local workflow. Check installed CLI help, target and project conventions before using them; they do not authorize writes to a remote or shared database. Keep hand-authored migrations and declarative generation on their respective project workflows.

## Verification and completion

Review generated SQL and the migration history for the intended environment. Run the affected checks or a relevant query against an appropriate test target. For authorization or exposure changes, read [security.md](security.md) and check the affected access model. Run available advisors when relevant to the change; report any check that could not be performed.

Complete when the requested schema change is represented in the repository’s migration workflow and its relevant behavior is verified. Apply or deploy only when that step is within the user’s authorization; an unknown remote target blocks that write, not preparation of a reviewable migration.
