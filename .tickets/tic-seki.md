---
id: tic-seki
status: open
deps: []
links: [tic-mwhy, tic-5cgv]
created: 2026-09-17T13:11:33Z
type: bug
priority: 2
assignee: namli
tags: [core, graph]
---
# Fix false cycles reported by tk dep cycle after the first real cycle

cmd_dep_cycle in the core script `ticket` (ticket:490-600) reports cycles that do not exist. Reproduced on master and feat/ticket-lint with four open tickets: a deps [b], b deps [a] (the only real cycle), c deps [a], d deps [a]. `tk dep cycle` prints "Cycle 1: a -> b -> a" and then a bogus "Cycle 2: d -> a" (with only ONE extra ticket pointing into the cycle the bug is hidden or not depending on awk iteration order; with two it always shows). Cause: dfs() returns as soon as it finds a cycle and never marks the nodes on the stack black, so they stay gray (state 1). The END loop then starts a new dfs from another ticket with a fresh `path`; when that walk reaches a leftover gray node it takes the "found cycle" branch, the path-extraction loop never finds the node in the new path, and the whole path plus the node is returned as a "cycle". `tk lint` (plugins/ticket-lint, check_cycles/dfs/record_cycle) reports only the real cycle on the same graph.

## Design

Make the search record a cycle at the back edge and keep going, always finishing the node: mark black on every exit path, start roots in a deterministic order, dedup by the normalised key that is already there. plugins/ticket-lint has this shape (dfs + record_cycle with an explicit stack) and can be ported; keep the current output format of `tk dep cycle` (Cycle N: path, then the member list) and keep ignoring closed tickets here - including closed tickets is the job of `tk lint`. Do not touch cmd_dep_tree.

## Acceptance Criteria

New scenario in features/ticket_dependencies.feature with the four-ticket graph above: output contains exactly one cycle and does not contain "d -> a" or "c -> a". A second scenario with two independent cycles still reports both. Existing dep cycle scenarios stay green; `make test` passes; CHANGELOG.md Fixed entry.

