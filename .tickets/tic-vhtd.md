---
id: tic-vhtd
status: open
deps: []
links: [tic-8qs0, tic-mwhy]
created: 2026-09-17T18:17:52Z
type: bug
priority: 2
assignee: namli
tags: [core, graph]
---
# Fix substring and regex matching of IDs in cmd_dep, cmd_undep, cmd_link and cmd_unlink

The core script `ticket` matches ticket IDs inside the deps/links arrays as unanchored patterns. cmd_dep (ticket:636) and cmd_link (ticket:1021) test presence with `_grep -q "$dep_id"` / `_grep -q "$target_id"`: an ID that is a substring (abc-001 vs abc-0012) or a regex match (a.b-0001 vs axb-0001) of an existing entry is reported as "already exists" and never added. cmd_undep (ticket:917) and cmd_unlink (ticket:1033) remove with `sed "s/, *$id//g; s/$id, *//g; s/$id//g"`: reproduced with deps [abc-0012, abc-001], `tk super undep x abc-001` leaves deps [2]; with deps [a.b-0001, axb-0001], `tk super undep c a.b-0001` removes BOTH and the ticket becomes ready. Realistic for IDs kept verbatim by plugins/ticket-migrate-beads (bd-1 / bd-12, bd-a3f8 / bd-a3f8.1). plugins/ticket-dep only works around it: the dep side reports "did not add", the undep side refuses when a sibling would be damaged (and, because bash =~ is ERE while sed is BRE, falsely refuses IDs containing + ? ( ) { } |).

## Design

Compare and remove whole array elements instead of patterns: split the [a, b] value on commas, trim, compare with ==, rebuild the array (awk or a bash loop; no regex built from an ID). One helper for deps and links. Afterwards drop the sibling pre-check from the undep mode of plugins/ticket-dep (keep the post-equality check) and bump its tk-plugin-version.

## Acceptance Criteria

Scenarios in features/ticket_dependencies.feature and features/ticket_links.feature through `ticket super`: dep/link of an ID that is a substring of an existing entry is added; undep/unlink of abc-001 next to abc-0012 leaves abc-0012 intact; undep of a.b-0001 next to axb-0001 removes only a.b-0001. The two "undep refuses when core would ..." scenarios in features/ticket_dep_guard.feature are replaced by scenarios that expect success, and "A dependency whose ID is a substring ..." expects the dependency to be added. make test passes; CHANGELOG.md Fixed entry and "### Plugins: ticket-dep" version bump.

