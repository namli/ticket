# ticket-lint: design

Ticket: `tic-5cgv`. Date: 2026-09-17.

## Goal

`tk` validates almost nothing: `tk dep A A` is accepted, hand edits and `tk super` can leave dangling references, and `tk dep cycle` ignores closed tickets. `tk lint` checks the whole `.tickets/` directory in one run and reports every broken invariant in a format that terminals, editors and CI can consume. It is the single "VERIFY" command for the `managing-tk-tickets` skill and a pre-commit hook for any project that uses `tk`.

## Non-goals

- No changes to the core `ticket` script.
- No fixing: lint only reports.
- No `.pre-commit-hooks.yaml`, no `--staged` mode (graph rules need every ticket anyway), no `--since` cut-off, no shellcheck CI, no skill rewrite (`tic-x75b`).

## CLI

```
tk lint [--conventions] [--strict]
```

| Flag | Effect |
|---|---|
| `--conventions` | Also run the convention rules (`close-note`, `dep-note`). Off by default so a plain run is clean on projects that do not follow the skill. |
| `--strict` | Warnings also cause exit 1. |
| `-h`, `--help` | Print usage on stdout, exit 0. |

Exit codes:

| Code | Meaning |
|---|---|
| 0 | No errors (warnings allowed unless `--strict`). Also for an empty tickets directory. |
| 1 | At least one error, or at least one warning with `--strict`. |
| 2 | Unknown flag or argument, or no tickets directory (`TICKETS_DIR` unset or not a directory). Message on stderr. When run through `tk`, a `TICKETS_DIR` that is set but missing is rejected by the core dispatcher with exit 1 before the plugin starts. |

## Output

One finding per line on stdout:

```
<path>:<line>: <level>: <message> [<rule>]
```

```
.tickets/tic-ab12.md:4: error: depends on itself [self-dep]
.tickets/tic-cd34.md:4: error: dependency cycle: tic-cd34 -> tic-ef56 -> tic-cd34 [dep-cycle]
.tickets/tic-gh78.md:3: warning: in_progress but blocked by open tic-cd34 [blocked-in-progress]
```

- `<path>`: `$TICKETS_DIR/<file>` with a leading `$PWD/` stripped, so paths are relative (clickable, usable by GitHub problem matchers and reviewdog `-efm="%f:%l: %m"`) when run from the repository root; otherwise as given.
- `<line>`: line of the offending front matter field; `1` when the field is absent or the finding concerns the whole ticket.
- `<level>`: `error` or `warning`.
- Sorted by path, then numerically by line (`LC_ALL=C sort -t: -k1,1 -k2,2n`), so output is deterministic.
- Summary `N errors, M warnings` on stderr, only when there is at least one finding. A clean run prints nothing on either stream.

## Rules

Principle: a closed ticket is history and gets no findings, except for the two rules every command depends on (`id-mismatch`, `invalid-status`) and the opt-in `close-note`.

| Rule | Level | Reported on | Condition |
|---|---|---|---|
| `id-mismatch` | error | any ticket, line of `id:` | `id:` is missing or differs from the file name without `.md`; a 0-byte file is reported as `empty file` |
| `invalid-status` | error | any ticket, line of `status:` | status is not `open`, `in_progress` or `closed` |
| `invalid-priority` | error | non-closed, line of `priority:` | priority is not a single digit 0-4 |
| `self-dep` | error | non-closed, line of `deps:` | the ticket's own id is in `deps` |
| `dep-cycle` | error | line of `deps:` | a cycle of length >= 2 in `deps` with at least one non-closed member. Closed tickets stay in the graph as edges (unlike `tk dep cycle`). Each cycle is reported once, on its non-closed member with the smallest id, and the message prints the path starting and ending at that member |
| `missing-dep` | error | non-closed, line of `deps:` | a dep id has no ticket file; one finding per missing id |
| `missing-link` | error | non-closed, line of `links:` | a link id has no ticket file; one finding per missing id |
| `missing-parent` | error | non-closed, line of `parent:` | the parent id has no ticket file |
| `parent-cycle` | error | non-closed, line of `parent:` | following `parent` from the ticket returns to it (includes a ticket that is its own parent) |
| `asymmetric-link` | error | non-closed, line of `links:` | the ticket links to an existing ticket that does not link back |
| `blocked-in-progress` | warning | line of `status:` | status is `in_progress` and an existing dep is not closed; one finding per open blocker |
| `open-child-of-closed` | warning | the non-closed child, line of `parent:` | the parent exists and is closed |
| `invalid-type` | warning | non-closed, line of `type:` | type is not `bug`, `feature`, `task`, `epic` or `chore` |
| `close-note` | warning, `--conventions` | closed ticket, line 1 | no line in the `## Notes` section starts with `Closed: ` |
| `dep-note` | warning, `--conventions` | non-closed, line of `deps:` | for a dep id, no line in the `## Notes` section starts with `Blocked by <dep-id>:`; one finding per dep |

Why some levels differ from the original ticket text:

- `invalid-type` is a warning: core does not validate `-t`, and `migrate-beads` imports foreign types.
- `blocked-in-progress` and `open-child-of-closed` are warnings: `tk` itself allows these states; they are process violations, not corrupt data. A project that wants them to block a commit uses `--strict`.

Known limitation: with `--conventions`, tickets closed before the conventions were adopted warn forever. If that becomes noise, add a `--since` cut-off in a separate ticket.

## Architecture

One file, `plugins/ticket-lint`, bash wrapper plus one awk program, following `cmd_ready`, `cmd_blocked`, `cmd_dep_cycle` and `plugins/ticket-query`.

```bash
#!/usr/bin/env bash
# tk-plugin: Check tickets for broken graph invariants and convention violations
# tk-plugin-version: 1.0.0
```

Wrapper:

1. Parse flags; anything else -> usage on stderr, exit 2.
2. Require `TICKETS_DIR` to be set and a directory, else exit 2. No `*.md` files -> exit 0.
3. Run awk once over `"$TICKETS_DIR"/*.md`, capturing stdout and the exit status (`out=$(awk ...) || rc=$?`, because the script runs under `set -euo pipefail`), then print `out` through `sort`. awk writes the summary straight to stderr and sets the exit status itself from the counts and the `strict` variable.

awk program:

- **Loading (main rules).** Front matter is strictly the lines between the first and the second `---` of a file; later `---` lines are body text. For each ticket store: file name id, `id`, `status`, `priority`, `type`, `parent`, the `deps` and `links` lists (brackets and spaces stripped, split on `,`), and the line number of each of those fields. After front matter, lines following a `## Notes` heading are stored per ticket as note lines.
- **Checks (END).** One function per rule group, each calling a single `emit(id, line, level, rule, msg)` that owns the output format and the counters: `check_ids()`, `check_fields()`, `check_deps()` (self, missing), `check_cycles()`, `check_links()` (missing, asymmetric), `check_parents()` (missing, cycle, open child of closed), `check_state()` (blocked in progress), and `check_conventions()` only when enabled.
- **Cycle detection.** The recursive colouring DFS and the smallest-id normalisation from `cmd_dep_cycle` (`ticket:490-600`), with two changes: closed tickets are kept in the graph, and a cycle whose members are all closed is dropped. Self-deps are skipped here (own rule). Missing targets are not traversed.
- **Portability.** POSIX awk only (mawk on Debian/Ubuntu, BSD awk on macOS): no `gensub`, `asorti`, three-argument `match`, `PROCINFO`. A backslash inside a bracket expression is a literal character in POSIX, so brackets are stripped with `/[][]/`, not `/[\[\]]/` (the prototype failed on busybox awk with the latter). No `tsort`, `jq`, `yq`, `git`.

## Testing

BDD, test-first, one rule at a time: scenario, see it fail, implement the rule, see it pass. `features/environment.py` already puts `plugins/` on PATH, so `ticket lint` resolves to the plugin.

`features/ticket_lint.feature`:

- clean repository: no output, exit 0; empty tickets directory: exit 0
- one scenario per rule (finding present: rule id, ticket id, level)
- closed-ticket exemption: closed ticket with a missing dep yields nothing
- cycle through a closed ticket is reported; cycle of only closed tickets is not
- cycle reported exactly once
- convention rules silent without `--conventions`, reported with it; a `Closed: ` / `Blocked by <id>:` note silences them
- `--strict`: warnings only -> exit 1; without it -> exit 0
- exact line format and sort order (two findings in two files)
- a `---` line in the body does not confuse parsing
- unknown flag -> exit 2; no tickets directory -> exit 2

New steps in `features/steps/ticket_steps.py`: set an arbitrary front matter field to a raw value; one-way link; append a note with given text; create a ticket file whose `id:` differs from its file name.

Full suite (`make test`) must stay green.

## Documentation and packaging

- `plugins/README.md`: `ticket-lint` section with the rule table, flags, exit codes, and two hook snippets: plain `.git/hooks/pre-commit` and a `repo: local` entry for the `pre-commit` framework.
- `README.md`: a short note in the Plugins section listing official plugins that are not part of `ticket-extras`. The usage block is unchanged (`lint` is not bundled; `tk help` lists installed plugins dynamically).
- `CHANGELOG.md`, `[Unreleased]` -> `### Plugins`: `ticket-lint 1.0.0: Check tickets for broken graph invariants and convention violations`.
- Not added to `pkg/extras.txt` (new plugin, not a core extraction). The release scripts package every file in `plugins/` individually, so `ticket-lint` ships as its own package.
