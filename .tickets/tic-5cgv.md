---
id: tic-5cgv
status: closed
deps: []
links: [tic-mwhy, tic-5lpp, tic-seki]
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

One awk pass over "$TICKETS_DIR"/*.md. Errors (exit 1): id missing or different from the file name (also an empty file); self-dep; cycle (including through closed tickets, unlike cmd_dep_cycle ticket:490); dep, link or parent pointing at a missing ticket; parent cycle; invalid status/priority; asymmetric link. Warnings (exit 0, exit 1 with --strict): in_progress ticket with an open blocker; open child of a closed parent; unknown type; and, only with --conventions: closed ticket without a `Closed: ` note; dep without a `Blocked by <id>:` note. Closed tickets get no findings except id, status and the Closed note. Output `.tickets/<id>.md:<line>: <level>: <message>`, one per line. Document a pre-commit hook snippet in plugins/README.md.

## Acceptance Criteria

Scenarios in features/ticket_lint.feature: one per rule, plus clean repo exits 0 with no output, --strict turns warnings into failure. Behave scenarios added and `make test` passes; README.md (Plugins section; the usage block lists bundled plugins only and `lint` is not bundled), plugins/README.md and CHANGELOG.md (### Plugins, version 1.0.0) updated; plugin has tk-plugin and tk-plugin-version metadata; NOT added to pkg/extras.txt (new plugin, not a core extraction).


## Notes

**2026-09-17T11:41:27Z**

Edited: design decisions from the tooling discussion (2026-09-17); output format in Design changed accordingly.

1. POSIX awk only. `awk` is mawk on Debian/Ubuntu and BSD awk on macOS, so no gawk extensions (gensub, asorti, 3-argument match, PROCINFO). No jq/yq: `tk query` exposes front matter only, while half of the rules read the Notes section, and front matter is flat and written by tk itself.
2. `tsort` (coreutils, POSIX) as the cheap first cycle check: feed it "<id> <dep>" pairs from ALL tickets, closed included. On a loop it prints "input contains a loop" plus the member nodes and exits 1. It gives neither the traversal order nor all cycles at once, so only when it fails run the DFS in awk to print a readable path `A -> B -> C -> A`. Self-deps are checked separately in awk.
3. Output format `.tickets/<id>.md:<line>: <level>: <message>` (gcc/shellcheck style) instead of `<id>: <level>: <message>`: clickable in terminals and VS Code, and consumable by GitHub Actions problem matchers and reviewdog (`-efm="%f:%l: %m"`) with no extra dependency. Use the line of the offending front matter field; line 1 for whole-ticket findings.

Rejected for this plugin: markdownlint / yamllint / vale (syntax and style only, blind to graph invariants), graphviz (visualisation, would be a separate `tk graph`), codegraph (indexes source code symbols, not ticket front matter; needs a daemon and index, contrary to the project's no-daemon stance).

**2026-09-17T11:47:02Z**

Edited: decision 2 above (tsort as first cycle check) is withdrawn. cmd_dep_cycle (ticket:490-600) already has a recursive DFS in awk that works on mawk, prints the path and dedups cycles; lint needs that DFS anyway for a readable path, so tsort would only add a second code path, a process and stderr parsing. Approach agreed with the user: one awk program inside plugins/ticket-lint (bash wrapper parses flags; main block loads all tickets, END runs one check_<rule>() function per rule), DFS adapted from cmd_dep_cycle but keeping closed tickets in the graph. Convention rules (Closed: / Blocked by notes) run only with --conventions, so a default run stays clean on projects that do not use the skill.

**2026-09-17T13:16:12Z**

Edited: Design and Acceptance aligned with the approved spec docs/superpowers/specs/2026-09-17-ticket-lint-design.md. Levels: blocked-in-progress, open-child-of-closed and invalid-type are warnings (tk itself allows these states; core does not validate -t), convention rules run only with --conventions, closed tickets are exempt except id/status/close-note; added id-mismatch and parent-cycle, which the original text did not list. README criterion: the usage block was deliberately left unchanged (lint is not part of ticket-extras, tk help lists plugins dynamically); a paragraph in the Plugins section points to it instead. Correction to the note above: the DFS was written anew rather than adapted from cmd_dep_cycle, whose search reports false cycles - see tic-seki.

**2026-09-17T13:16:12Z**

Closed: done - plugins/ticket-lint 1.0.0: tk lint [--conventions] [--strict], 15 rules, file:line output, exit codes 0/1/2; 35 behave scenarios (make test: 159 scenarios, 0 failed; same 35 green under busybox awk); documented in plugins/README.md, README.md and CHANGELOG.md; whole-branch review: ready to merge. Not executed on BSD awk / bash 3.2 (reviewed by reading only). Follow-ups: tic-gqng, tic-hxgf (lint), tic-seki, tic-xj6g (core bugs found on the way).
