---
id: tic-6rw0
status: closed
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

**2026-09-17T15:15:00Z**

Guard style decided in tic-zmz1: option A - plugins/ticket-start and plugins/ticket-reopen shadow built-in 'tk start' / 'tk reopen'. Reason: plugin dispatch (ticket:1334) checks PATH before built-ins, so shadowing needs no core change and keeps the fork mergeable with upstream wedow/ticket; an agent typing the built-in name from habit still hits the guard; escape hatches are 'tk super <cmd>' and --force. Caveat: the guard exists only where the plugins are on PATH, so the skill must fail loudly when they are missing (see tic-x75b).

**2026-09-17T15:23:06Z**

Design update from tic-5lpp: the re-blocked dependents are the 'ready' lines of 'tk impact --porcelain <id>' taken while the ticket is still closed. Spec: docs/superpowers/specs/2026-09-17-ticket-impact-design.md

**2026-09-17T16:56:25Z**

Design decisions (spec docs/superpowers/specs/2026-09-17-ticket-start-reopen-guard-design.md): two files, both thin consumers of 'tk impact --porcelain' (status / blocker / ready lines), IDs resolved through 'tk super show'; 'tk start' on a closed ticket is always refused and points to 'tk reopen -m <reason> --in-progress' (--force does not override it); --force on start overrides open blockers and writes a 'Forced start: open blockers ...' note; 'tk reopen --in-progress' applies the same blocker guard, --force overrides it and adds a 'Forced: ...' second line to the Reopened note; plain reopen is never refused; reopen of a non-closed ticket -> exit 0, no note, status untouched.

**2026-09-17T18:10:25Z**

Closed: done - plugins/ticket-start and plugins/ticket-reopen (1.0.0) shadow tk start / tk reopen: start refuses blocked and closed tickets (--force overrides blockers, writes a Forced start note); reopen requires -m, writes the Reopened note, supports --in-progress (guarded, --force) and reports re-blocked dependents; IDs resolved from front matter with a round-trip check, empty IDs rejected; 54 scenarios, make test 264/0, busybox awk green; README, plugins/README, CHANGELOG, publish-script deps on ticket-impact and minimal skill edits done. PR https://github.com/namli/ticket/pull/5
