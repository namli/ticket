---
id: tic-zmz1
status: closed
deps: []
links: []
created: 2026-09-17T11:29:13Z
type: task
priority: 1
assignee: namli
parent: tic-sa3b
tags: [plugins, design]
---
# Decide guard style: shadow built-ins, new verbs, or core changes

Open question from the brainstorming session, not yet answered by the user. It shapes plugins/ticket-close, plugins/ticket-start, plugins/ticket-reopen, plugins/ticket-dep, plugins/ticket-undep. Options: (A, recommended) plugins shadow the built-in names via the plugin dispatch in `ticket` (main dispatch, ~ticket:1310), so an agent typing `tk close` from habit still hits the guard, with `tk super close` and --force as escape hatches; (B) new verbs such as `tk resolve` / `tk begin` / `tk block`, built-ins untouched, but the skill must still forbid `tk close`; (C) put the guards and --reason/--force flags into cmd_close/cmd_start/cmd_reopen/cmd_dep in the core script, which diverges the fork namli/ticket from upstream wedow/ticket; (D) no guards, only read-only helpers.

## Acceptance Criteria

User has chosen one option; choice and reason recorded as a note here and on the three guard tickets; their titles/designs adjusted if the choice is not A.


## Notes

**2026-09-17T15:15:00Z**

Decision (user, 2026-09-17): option A - plugins shadow the built-in names. Reason: plugin dispatch (ticket:1334) checks PATH before built-ins, so shadowing needs no core change and keeps the fork mergeable with upstream wedow/ticket; an agent typing the built-in name from habit still hits the guard; escape hatches are 'tk super <cmd>' and --force. Caveat: the guard exists only where the plugins are on PATH, so the skill must fail loudly when they are missing (see tic-x75b). Rejected: B keeps a manual 'never tk close' rule in the skill, C diverges the fork from upstream, D does not reach the epic's goal.

**2026-09-17T15:16:19Z**

Closed: done - option A chosen, recorded on tic-yxrw, tic-6rw0, tic-mwhy
