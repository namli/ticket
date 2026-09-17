---
id: tic-gqng
status: open
deps: [tic-5cgv]
links: [tic-hxgf]
created: 2026-09-17T13:11:33Z
type: bug
priority: 4
assignee: namli
tags: [plugins, lint]
---
# ticket-lint: line-number sort breaks when the printed path contains a colon

plugins/ticket-lint sorts findings with `LC_ALL=C sort -t: -k1,1 -k2,2n`. When the PRINTED part of the path contains a colon the second key is a path fragment, not the line number, so lines sort as text (11 before 4). This only happens when tk lint runs from outside the repository root (the wrapper strips a leading "$PWD/") under a directory whose name contains ":". Reproduced in the final review with TICKETS_DIR="<dir>/my proj:v2/.tickets": "c-1.md:11: ..." was printed before "c-1.md:4: ...". From the repository root the order is correct. Output stays deterministic, so severity is low. Found by the whole-branch review of tic-5cgv (finding M2).

## Design

Stop sorting on the display string: have emit() in the awk program print a sort key in front of each finding - "<id>\t<line>\t<finding>" - sort in the wrapper with a tab separator (-t "$(printf "\t")" -k1,1 -k2,2n) and cut the key off (cut -f3-). Ticket ids cannot contain a tab. The same restructuring of the awk-to-wrapper pipeline can fix the summary ordering ticket at no extra cost; consider doing both together.

## Acceptance Criteria

New scenario in features/ticket_lint.feature: tickets directory under a directory with ":" in its name, command run from outside it with TICKETS_DIR set, findings on a line below 10 and on a line of 10 or more in one ticket come out in numeric order. Existing 35 lint scenarios stay green, also under busybox awk. plugins/ticket-lint tk-plugin-version 1.0.1 and CHANGELOG.md "### Plugins" entry.


## Notes

**2026-09-17T13:11:33Z**

Blocked by tic-5cgv: plugins/ticket-lint exists only on branch feat/ticket-lint until tic-5cgv is merged; this ticket changes that file
