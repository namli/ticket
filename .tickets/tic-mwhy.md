---
id: tic-mwhy
status: closed
deps: [tic-zmz1]
links: [tic-5cgv, tic-seki, tic-vhtd]
created: 2026-09-17T11:29:13Z
type: feature
priority: 1
assignee: namli
parent: tic-sa3b
tags: [plugins, guards, graph]
---
# Add guarded dep and undep plugins: reject self-deps and cycles, record the reason

Plugins plugins/ticket-dep and plugins/ticket-undep (names depend on the guard-style decision). cmd_dep (ticket:601) accepts `tk dep A A` and cycles, and its duplicate check `_grep -q "$dep_id"` on the deps line is a substring match. cmd_dep_cycle (ticket:490) only looks at open tickets. Replaces SKILL.md Creating steps 4-5, editing.md step 3 notes, and the "Dep without a reason" mistake.

## Design

dep: pass `tree` and `cycle` subcommands straight to `"$TK_SCRIPT" super dep`. Otherwise resolve both IDs, reject id == dep-id, reject when dep-id already reaches id through deps (walk in awk), then call super dep. `--reason <text>` (required unless --no-note) writes `Blocked by <dep-id>: <text>` on the blocked ticket. Finish by printing whether the ticket is now ready or blocked. undep: `--reason` writes `No longer blocked by <dep-id>: <text>`, then prints ready/blocked state.

## Acceptance Criteria

Scenarios in features/ticket_dep_guard.feature: self-dep rejected; 2- and 3-node cycle rejected and file unchanged; note written with exact prefix; dep tree / dep cycle still work through the plugin; undep note written; state line printed. Behave scenarios added and `make test` passes; README.md usage block, plugins/README.md and CHANGELOG.md (### Plugins, version 1.0.0) updated; plugin has tk-plugin and tk-plugin-version metadata; NOT added to pkg/extras.txt (new plugin, not a core extraction).


## Notes

**2026-09-17T11:29:13Z**

Blocked by tic-zmz1: plugin names and whether they shadow `tk dep` / `tk undep` are not decided yet

**2026-09-17T13:11:34Z**

Related tic-seki: `tk dep cycle` reports false cycles after the first real one; do not rely on its output in the dep guard until that is fixed (write the reachability walk in the plugin, as the design already says).

**2026-09-17T15:15:00Z**

Guard style decided in tic-zmz1: option A - plugins/ticket-dep and plugins/ticket-undep shadow built-in 'tk dep' / 'tk undep' ('tk dep tree' and 'tk dep cycle' must keep working through the plugin). Reason: plugin dispatch (ticket:1334) checks PATH before built-ins, so shadowing needs no core change and keeps the fork mergeable with upstream wedow/ticket; an agent typing the built-in name from habit still hits the guard; escape hatches are 'tk super <cmd>' and --force. Caveat: the guard exists only where the plugins are on PATH, so the skill must fail loudly when they are missing (see tic-x75b).

**2026-09-17T16:14:37Z**

Design decisions (namli, 2026-09-17), spec: docs/superpowers/specs/2026-09-17-ticket-dep-guard-design.md. (1) --reason is required for dep AND undep unless --no-note. (2) No --force: self-dep and cycle are never legitimate, the only bypass is 'tk super dep'. (3) One script plugins/ticket-dep + symlink plugins/ticket-undep. (4) Existing scenarios that test the built-in dep/undep switch to 'ticket super dep|undep' because features/environment.py puts plugins/ on PATH; same rule applies to tic-yxrw and tic-6rw0. (5) Minimal SKILL.md / editing.md edits are in scope so the skill does not contradict the tool before tic-x75b.

**2026-09-17T18:18:15Z**

Closed: done - plugins/ticket-dep 1.0.0 + symlink plugins/ticket-undep shadow tk dep / tk undep: self-deps and cycles refused, exact ID comparison, --reason notes (Blocked by / No longer blocked by), state line, undep refuses when core would damage a sibling dep; 45 scenarios in features/ticket_dep_guard.feature, make test 225/225; follow-ups tic-vhtd, tic-8qs0
