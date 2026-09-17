---
id: tic-6rw0
status: open
deps: [tic-zmz1]
links: []
created: 2026-09-17T11:29:13Z
type: feature
priority: 2
assignee: namli
parent: tic-sa3b
tags: [plugins, guards, lifecycle]
---
# Add guarded start and reopen plugins

Plugins plugins/ticket-start and plugins/ticket-reopen (names depend on the guard-style decision). cmd_start (ticket:267) starts blocked tickets; cmd_reopen (ticket:283) silently re-blocks dependents, always sets `open` and records no reason. Replaces two items of "tk facts that bite" and the Reopening paragraph in skills/managing-tk-tickets/SKILL.md.

## Design

start: refuse when any dep is not closed, print the open blockers, --force overrides. reopen: usage tk reopen <id> -m <reason> [--in-progress]; write note `Reopened: <reason>` via super add-note, set status open or in_progress via super status, then print the dependents that went back to blocked.

## Acceptance Criteria

Scenarios in features/ticket_start_guard.feature and features/ticket_reopen_guard.feature: start refused on blocked ticket, allowed when blockers closed, --force works; reopen without -m fails; note written; --in-progress sets in_progress; re-blocked dependents listed. Behave scenarios added and `make test` passes; README.md usage block, plugins/README.md and CHANGELOG.md (### Plugins, version 1.0.0) updated; plugin has tk-plugin and tk-plugin-version metadata; NOT added to pkg/extras.txt (new plugin, not a core extraction).


## Notes

**2026-09-17T11:29:13Z**

Blocked by tic-zmz1: plugin names and whether they shadow `tk start` / `tk reopen` are not decided yet
