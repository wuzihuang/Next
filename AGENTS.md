# Next

NextBody-Hoop. See `README.md` for the project, `docs/STATUS.md` for current state.

## Agent skills

### TypeSafe

Use the [TypeSafe skill](.agents/skills/typesafe-ai/SKILL.md) for this project's
TypeSafe/Jev integration and AI decision workflows. Read the relevant live TypeSafe
docs before changing API contracts or questions. Keep `TYPESAFE_API_KEY` server-side;
local credentials belong in the ignored `supabase/.env`, never in source or logs.

### Issue tracker

Issues live as GitHub issues in `wuzihuang/Next`, driven by the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
