---
id: tic-sa3b
status: open
deps: []
links: []
created: 2026-09-17T11:29:13Z
type: epic
priority: 2
assignee: namli
tags: [plugins, skill]
---
# Add guard and lifecycle plugins that back the managing-tk-tickets skill

The skill skills/managing-tk-tickets/SKILL.md and editing.md is long because the core script `ticket` validates almost nothing: cmd_close, cmd_start, cmd_reopen (ticket:267-289) are one-line wrappers over cmd_status, cmd_dep (ticket:601) accepts self-deps and cycles, no command edits title/priority/tags/parent, and content search needs a grep pipeline. Reproduced: `tk dep A A` accepted, `tk start` works on a blocked ticket, closing a parent with an open child moves the child to `tk ready`. Goal: move every mechanical rule of the skill into plugins under plugins/, so the skill keeps only judgment (classification, STOP AND ASK before close).

## Design

One plugin per command under plugins/ticket-<name>, bash + awk like the core, calling built-ins via "$TK_SCRIPT super <cmd>". Children: guarded close, guarded start/reopen, guarded dep/undep, impact, find, set, lint, redep/merge (deferred), then shrink the skill. Open decision (own ticket): guards shadow built-in names vs new verbs vs core changes.

## Acceptance Criteria

All child tickets closed; SKILL.md no longer asks the agent to perform a check that a plugin enforces.

