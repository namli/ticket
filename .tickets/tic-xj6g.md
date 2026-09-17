---
id: tic-xj6g
status: open
deps: []
links: [tic-vezj, tic-tpuf]
created: 2026-09-17T13:11:33Z
type: bug
priority: 3
assignee: namli
tags: [core, portability]
---
# Fix non-POSIX bracket expressions that break tk under busybox and strict POSIX awk

The core script and the ls plugin strip YAML list brackets with gsub(/[\[\] ]/, "", x). In POSIX a backslash inside a bracket expression is a literal character, so strict implementations parse this as the set {backslash, [} followed by literal text and strip nothing. mawk and gawk tolerate it; busybox awk does not. Reproduced with busybox awk first in PATH: `tk blocked` prints "x [P2][open] - x <- [[y]]" instead of "<- [y]", and because the stored dep id becomes "[y]" it never matches a ticket id, so dependency resolution in ready/blocked is wrong (a closed blocker still blocks). Affected lines: ticket:319, 503, 677, 680, 771, 814, 817, 1063, 1064 (pattern /[\[\] ]/) and ticket:962 (/[\[\]]/); plugins/ticket-ls:29 and :32 (plugins/ticket-list is an alias of the same file). plugins/ticket-query is NOT affected: it uses /^\[|\]$/ outside a bracket expression. Found while prototyping plugins/ticket-lint, which uses the portable form.

## Design

Replace every occurrence with the POSIX-correct form used in plugins/ticket-lint: gsub(/[][]/, "", x); gsub(/[ \t]/, "", x) - "]" first inside the brackets makes it literal. Where the space must stay (ticket:962 strips brackets only) use /[][]/ alone. No behaviour change on mawk/gawk/BSD awk. Bump tk-plugin-version of ticket-ls to 1.0.1.

## Acceptance Criteria

No awk regex in `ticket` or plugins/* contains a backslash inside a bracket expression any more (search for the two characters "[" + backslash). With busybox awk first in PATH (shim script `exec busybox awk "$@"` named awk) the scenarios of features/ticket_listing.feature and features/ticket_dependencies.feature pass, as they do with the system awk. `make test` passes. CHANGELOG.md: Fixed entry for core and "### Plugins: ticket-ls 1.0.1".


## Notes

**2026-09-17T18:17:52Z**

Related tic-mwhy: with busybox awk first in PATH the scenario 'dep tree works through the plugin' in features/ticket_dep_guard.feature fails too (44/45), because the built-in 'tk super dep tree' drops children (ticket:319). It turns green with this fix; add features/ticket_dep_guard.feature to the busybox acceptance run.
