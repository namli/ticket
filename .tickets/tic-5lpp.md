---
id: tic-5lpp
status: closed
deps: []
links: [tic-5cgv, tic-12tn]
created: 2026-09-17T11:29:13Z
type: feature
priority: 1
assignee: namli
parent: tic-sa3b
tags: [plugins, graph]
---
# Add ticket-impact plugin: show what closing a ticket would change

New read-only plugin plugins/ticket-impact, used as `tk impact <id>`. Replaces the manual reasoning in skills/managing-tk-tickets/SKILL.md Closing step 3 and step 5 and the "Won't do / duplicate / superseded" paragraph. For the given ticket print: open Blockers; open Children; dependents (tickets whose deps contain the id, same data as **Blocking** in cmd_show, ticket:1039) split into "becomes ready" (no other open blocker) and "still blocked by <ids>"; whether it is the last open child of its parent.

## Design

Single awk pass over "$TICKETS_DIR"/*.md like cmd_ready (ticket:653) and cmd_blocked (ticket:790). Support partial IDs by resolving through `"$TK_SCRIPT" super show` or the same find logic as ticket_path (ticket:105). Add a machine-readable mode (--ids-ready) so plugins/ticket-close can reuse it instead of duplicating graph logic.

## Acceptance Criteria

Scenarios in features/ticket_impact.feature: dependent with single blocker listed as becomes-ready; dependent with a second open blocker listed as still blocked; open children listed; last-child case reported; closed dependents ignored; partial ID works. Behave scenarios added and `make test` passes; README.md usage block, plugins/README.md and CHANGELOG.md (### Plugins, version 1.0.0) updated; plugin has tk-plugin and tk-plugin-version metadata; NOT added to pkg/extras.txt (new plugin, not a core extraction).


## Notes

**2026-09-17T15:23:06Z**

Design decided (user, 2026-09-17), spec: docs/superpowers/specs/2026-09-17-ticket-impact-design.md. --porcelain replaces --ids-ready: one stable line-per-fact mode (status / blocker / child / ready / blocked / last-child), because ticket-close also needs open blockers and open children, which a list of ready IDs cannot carry. Every fact is computed as if the target were closed; on an already closed target the human output says 'Already closed. Reopening would re-block:'.

**2026-09-17T16:34:23Z**

Closed: done - plugins/ticket-impact 1.0.0: tk impact [--porcelain] <id>, 30 scenarios in features/ticket_impact.feature. Deviations from the ticket text: --porcelain replaces --ids-ready; README.md gets a Plugins-section sentence instead of a usage-block line (same treatment as ticket-lint). Remaining test gaps: tic-12tn.
