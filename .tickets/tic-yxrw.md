---
id: tic-yxrw
status: in_progress
deps: [tic-zmz1, tic-5lpp]
links: []
created: 2026-09-17T11:29:13Z
type: feature
priority: 1
assignee: namli
parent: tic-sa3b
tags: [plugins, guards, lifecycle]
---
# Add guarded close plugin with resolution reason and unblock report

Plugin plugins/ticket-close (name depends on the guard-style decision). Today cmd_close (ticket:275) is `cmd_status "$1" closed`: it closes blocked tickets and parents with open children and records no reason, so dependents silently appear in `tk ready`. Replaces SKILL.md Closing steps 1, 4, 5, the note-prefix rule and two rows of Common mistakes.

## Design

Usage: tk close <id> --reason done|wontdo|duplicate|superseded [-m text] [--ref <id>] [--force]. Refuse (exit 1, explain) when the ticket has open Blockers or open Children unless --force. --reason required; duplicate/superseded require --ref. For wontdo/duplicate/superseded refuse while open dependents exist (they would become falsely ready) unless --force, and list them. Write the note through `"$TK_SCRIPT" super add-note` with the exact prefixes `Closed: done - `, `Closed: won't do - `, `Closed: duplicate of <id>`, `Closed: superseded by <id>`, then `"$TK_SCRIPT" super close`. Afterwards print tickets that became ready (reuse `tk impact --ids-ready`) and "last child closed, consider closing parent <id>". Does NOT replace the STOP AND ASK step of the skill.

## Acceptance Criteria

Scenarios in features/ticket_close_guard.feature: refuses with open blocker; refuses with open child; --force overrides; missing --reason fails; note text has the right prefix for each reason; wontdo with open dependents refused; unblocked tickets printed; parent hint printed; `tk super close` still bypasses. Behave scenarios added and `make test` passes; README.md usage block, plugins/README.md and CHANGELOG.md (### Plugins, version 1.0.0) updated; plugin has tk-plugin and tk-plugin-version metadata; NOT added to pkg/extras.txt (new plugin, not a core extraction).


## Notes

**2026-09-17T11:29:13Z**

Blocked by tic-zmz1: plugin name and whether it shadows `tk close` are not decided yet

**2026-09-17T11:29:13Z**

Blocked by tic-5lpp: close reports newly ready tickets and refuses on false-ready dependents by calling `tk impact --ids-ready` instead of duplicating the graph logic

**2026-09-17T15:15:00Z**

Guard style decided in tic-zmz1: option A - plugins/ticket-close shadows built-in 'tk close'. Reason: plugin dispatch (ticket:1334) checks PATH before built-ins, so shadowing needs no core change and keeps the fork mergeable with upstream wedow/ticket; an agent typing the built-in name from habit still hits the guard; escape hatches are 'tk super <cmd>' and --force. Caveat: the guard exists only where the plugins are on PATH, so the skill must fail loudly when they are missing (see tic-x75b).

**2026-09-17T15:23:06Z**

Design update from tic-5lpp: 'reuse tk impact --ids-ready' now reads 'tk impact --porcelain' - blocker / child lines for the guard, ready lines for the unblock report, last-child for the parent hint. Spec: docs/superpowers/specs/2026-09-17-ticket-impact-design.md

**2026-09-17T16:34:15Z**

Open design question from the tic-5lpp final review, deferred here by the user (2026-09-17): add a 'target <full-id>' line to 'tk impact --porcelain' so ticket-close / ticket-reopen do not re-resolve a partial ID themselves (a third copy of the find block). Additive, legal within the 1.x porcelain contract (consumers ignore unknown kinds). Decide when designing ticket-close.

**2026-09-17T16:49:28Z**

Design decisions (spec docs/superpowers/specs/2026-09-17-ticket-close-guard-design.md): no 'target' line in 'tk impact --porcelain' - target and --ref are resolved through 'tk super show' (no copy of the find block, ticket-impact stays 1.0.0); -m required for done/wontdo, optional for duplicate/superseded; one --force overrides all guards and adds a 'Forced: ...' second line to the Closed note; already closed -> exit 0, no note.
