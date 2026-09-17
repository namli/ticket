---
id: tic-5cgv
status: open
deps: []
links: [tic-mwhy, tic-5lpp]
created: 2026-09-17T11:29:13Z
type: feature
priority: 2
assignee: namli
parent: tic-sa3b
tags: [plugins, graph, guards]
---
# Add ticket-lint plugin: verify graph and convention invariants, usable as pre-commit hook

New plugin plugins/ticket-lint, used as `tk lint`. Replaces the VERIFY steps spread over skills/managing-tk-tickets/SKILL.md and editing.md and catches damage done with `tk super` or by hand-editing.

## Design

One awk pass over "$TICKETS_DIR"/*.md. Errors (exit 1): self-dep; cycle (including through closed tickets, unlike cmd_dep_cycle ticket:490); dep, link or parent pointing at a missing ticket; invalid status/priority/type; in_progress ticket with an open blocker; closed ticket with an open child; asymmetric link. Warnings (exit 0, exit 1 with --strict): closed ticket without a `Closed: ` note; dep without a `Blocked by <id>:` note. Output `.tickets/<id>.md:<line>: <level>: <message>`, one per line. Document a pre-commit hook snippet in plugins/README.md.

## Acceptance Criteria

Scenarios in features/ticket_lint.feature: one per rule, plus clean repo exits 0 with no output, --strict turns warnings into failure. Behave scenarios added and `make test` passes; README.md usage block, plugins/README.md and CHANGELOG.md (### Plugins, version 1.0.0) updated; plugin has tk-plugin and tk-plugin-version metadata; NOT added to pkg/extras.txt (new plugin, not a core extraction).


## Notes

**2026-09-17T11:41:27Z**

Edited: design decisions from the tooling discussion (2026-09-17); output format in Design changed accordingly.

1. POSIX awk only. `awk` is mawk on Debian/Ubuntu and BSD awk on macOS, so no gawk extensions (gensub, asorti, 3-argument match, PROCINFO). No jq/yq: `tk query` exposes front matter only, while half of the rules read the Notes section, and front matter is flat and written by tk itself.
2. `tsort` (coreutils, POSIX) as the cheap first cycle check: feed it "<id> <dep>" pairs from ALL tickets, closed included. On a loop it prints "input contains a loop" plus the member nodes and exits 1. It gives neither the traversal order nor all cycles at once, so only when it fails run the DFS in awk to print a readable path `A -> B -> C -> A`. Self-deps are checked separately in awk.
3. Output format `.tickets/<id>.md:<line>: <level>: <message>` (gcc/shellcheck style) instead of `<id>: <level>: <message>`: clickable in terminals and VS Code, and consumable by GitHub Actions problem matchers and reviewdog (`-efm="%f:%l: %m"`) with no extra dependency. Use the line of the offending front matter field; line 1 for whole-ticket findings.

Rejected for this plugin: markdownlint / yamllint / vale (syntax and style only, blind to graph invariants), graphviz (visualisation, would be a separate `tk graph`), codegraph (indexes source code symbols, not ticket front matter; needs a daemon and index, contrary to the project's no-daemon stance).
