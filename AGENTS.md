# Next

NextBody-Hoop. See `README.md` for the project, `docs/STATUS.md` for current state.

## Ship both platforms

Every app code change lands in both iOS (`app/NextBody/`) and Android (`android/`) in the
same task. A change is done only when both sides behave the same.

## AI folders are off limits

App AI is hidden, not deleted. Its code lives in two folders:

- `app/NextBody/AI/` — Chat, Plan, AI memory, the model client, voice and phone tools
- `supabase/functions/_shared/ai/` — prompts, tools, quota, coach and plan

**Do not open, read, search, edit, move or delete anything in these two folders without
the owner's explicit permission in the current conversation.** Exclude them from searches
(for example `rg --glob '!**/AI/**' --glob '!**/_shared/ai/**'`). If a task seems to need
them, stop and ask first.

The switches live outside those folders and may be read without asking:
`app/NextBody/App/AIFeature.swift` (`enabled = false`) and
`supabase/functions/_shared/ai-switch.ts`, which answers 410
`AI_DISABLED` from `turn`, `asr`, `memory-settle` and `screen-current` unless the Edge
Function secret `AI_ENABLED=1`. Changing a switch still needs the owner's permission.

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
