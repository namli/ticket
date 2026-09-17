# Ticket Plugins

Official plugins that extend `tk` with additional commands.

## Writing Plugins

Plugins are executables named `tk-<cmd>` or `ticket-<cmd>` in `$PATH`. This repo uses the `ticket-` prefix for consistency.

Required metadata in the first 10 lines:

```bash
#!/usr/bin/env bash
# tk-plugin: sync tickets with GitHub issues
# tk-plugin-version: 1.0.0

set -euo pipefail
# implementation here
```

## Environment Variables

Plugins receive:
- `TICKETS_DIR` — absolute path to `.tickets/` directory
- `TK_SCRIPT` — absolute path to the `tk` script

Use `$TK_SCRIPT super <cmd>` to call built-ins without recursing into plugins:

```bash
#!/usr/bin/env bash
# tk-plugin: wrapper that creates tickets with defaults
# tk-plugin-version: 1.0.0

"$TK_SCRIPT" super create "$@" --type task --priority 1
```

## Packaging

Plugins here are automatically packaged on release for Homebrew and AUR.

**Meta-packages:**
- `ticket-core` — core script only
- `ticket-extras` — curated plugins (listed in `pkg/extras.txt`)
- `ticket` — depends on core + extras

**Install options:**
```bash
brew install ticket                      # Full: core + curated plugins
brew install ticket-core                 # Minimal: core only
brew install ticket-core ticket-query    # Core + specific plugin
```

## Adding a Plugin

1. Create `plugins/ticket-<name>` with metadata comments
2. `chmod +x plugins/ticket-<name>`
3. Add to `pkg/extras.txt` if it should be in the extras bundle
4. Commit and tag a release

## ticket-find

`tk find [--all] [-T tag] <pattern> [pattern...]` searches ticket content - the part `tk query` does not return - and prints one list line per matching ticket, sorted by ID:

```
$ tk find 'SessionStore' 'src/Auth/'
nw-5c46  [P1][in_progress] - Add SSE connection management
nw-7a21  [P2][open] - Expire idle sessions
```

Patterns are case-insensitive POSIX extended regexes matched line by line against the title, body and notes; front matter is not searched, so `tk find open` does not match every `status: open`. Several patterns are OR-ed. Use `--` before a pattern that starts with a dash.

| Flag | Effect |
|---|---|
| `--all` | include closed tickets (there is no `-a` short form: `-a` means assignee in `ls`, `ready`, `blocked` and `closed`) |
| `-T X`, `--tag=X` | only tickets tagged `X` (whole tag, like `tk ls -T`) |

Exit codes follow `grep`: `0` at least one match, `1` no match, `2` usage error, invalid regex or no `.tickets` directory found.

Requires only bash and POSIX awk.

## ticket-lint

`tk lint [--conventions] [--strict]` checks every ticket in `.tickets/` in one pass and prints one finding per line, sorted by file and line:

```
.tickets/nw-5c46.md:4: error: depends on itself [self-dep]
.tickets/nw-7a21.md:3: warning: in_progress but blocked by open nw-5c46 [blocked-in-progress]
```

The format is the one compilers use, so paths are clickable in terminals and editors and work with GitHub problem matchers or reviewdog (`-efm="%f:%l: %m"`). A summary (`2 errors, 1 warning`) goes to stderr; a clean run prints nothing.

| Rule | Level | Meaning |
|---|---|---|
| `id-mismatch` | error | `id:` is missing or differs from the file name (also: empty file) |
| `invalid-status` | error | status is not `open`, `in_progress` or `closed` |
| `invalid-priority` | error | priority is not 0-4 |
| `self-dep` | error | ticket depends on itself |
| `dep-cycle` | error | dependency cycle with at least one non-closed member (closed tickets count as edges, unlike `tk dep cycle`) |
| `missing-dep`, `missing-link`, `missing-parent` | error | reference to a ticket that does not exist |
| `parent-cycle` | error | the `parent` chain leads back to the ticket |
| `asymmetric-link` | error | A links to B but B does not link back |
| `blocked-in-progress` | warning | `in_progress` ticket with a non-closed dependency |
| `open-child-of-closed` | warning | parent is closed, child is not |
| `invalid-type` | warning | type is not `bug`, `feature`, `task`, `epic` or `chore` |
| `close-note` | warning, `--conventions` | closed ticket without a `Closed: ...` note |
| `dep-note` | warning, `--conventions` | dependency without a `Blocked by <id>: ...` note |

Closed tickets are history: apart from `id-mismatch`, `invalid-status` and `close-note` they produce no findings.

| Flag | Effect |
|---|---|
| `--conventions` | also check the note conventions of the `managing-tk-tickets` skill |
| `--strict` | warnings fail the run too |

Exit codes: `0` no errors, `1` errors (or warnings with `--strict`), `2` unknown option or no `.tickets` directory found (a `TICKETS_DIR` that is set but missing is rejected by `tk` itself with exit 1).

Requires only bash, POSIX awk and `sort`.

### As a pre-commit hook

Plain git hook, `.git/hooks/pre-commit` (make it executable):

```sh
#!/bin/sh
tk lint || exit 1
```

With the [pre-commit](https://pre-commit.com) framework, in `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: local
    hooks:
      - id: tk-lint
        name: tk lint
        entry: tk lint
        language: system
        files: ^\.tickets/
        pass_filenames: false
```

## ticket-impact

`tk impact [--porcelain] <id>` shows what closing a ticket would change. It is read-only and accepts one full or partial ID.

```
$ tk impact nw-5c46
nw-5c46 [in_progress] Add SSE connection management

Open blockers:
- nw-1d09 [open] Pick the reconnect strategy

Becomes ready:
- nw-7a21 [open] Stream ticket updates to the UI

Still blocked by others:
- nw-9f3e [open] Release 0.5 <- nw-2b77

Last open child of nw-0a11 [open] Realtime epic - consider closing the parent
```

Every fact is computed as if the ticket were already closed: a dependent is "ready" when all its other dependencies are closed, a dangling dependency counts as open, and only direct dependents are examined. On a ticket that is already closed the heading reads `Already closed. Reopening would re-block:`, so the same command answers what a reopen would undo. A ticket with no relations prints `No impact: nothing depends on <id>`.

Exit codes: 0 impact printed, 1 ticket not found or ambiguous ID, 2 usage error or no tickets directory.

### Porcelain

`--porcelain` prints one fact per line for other plugins and scripts:

```
status <status>
blocker <id>
child <id>
ready <id>
blocked <id> <dep>[,<dep>...]
last-child <parent-id>
```

`status` is always the first line. Kinds appear in this order, lines of one kind are sorted by ID, and a kind without facts prints nothing. Consumers must match on the first word and ignore kinds they do not know; existing kinds and their field order do not change within 1.x.

Any status other than `closed` counts as open. IDs and statuses are assumed to contain no whitespace and no commas, which holds for everything `tk` generates.

```bash
out=$("$TK_SCRIPT" impact --porcelain "$id") || exit $?
if grep -qE '^blocker |^child ' <<<"$out"; then
    echo "refusing to close $id: open blockers or children" >&2
    exit 1
fi
awk '$1 == "ready" { print $2 }' <<<"$out"   # tickets that become ready
```

Requires only bash, POSIX awk, `find` and `grep`.

## ticket-close

`ticket-close` shadows the built-in `tk close`. The built-in closes anything and records nothing; because ANY closed dependency counts as resolved, a wrong close silently moves dependents to `tk ready`. The guard refuses unsafe closes, records the resolution and reports the effect.

```
tk close <id> --reason done|wontdo|duplicate|superseded [-m <text>] [--ref <id>] [--force]
```

| Flag | Effect |
|---|---|
| `--reason <r>`, `--reason=<r>` | Resolution, required. |
| `-m <text>` | Free text for the note. Required for `done` and `wontdo`, optional for `duplicate` and `superseded`. |
| `--ref <id>`, `--ref=<id>` | The ticket this one duplicates / is superseded by (full or partial ID). Required for `duplicate` and `superseded`, rejected otherwise. |
| `--force` | Close although a guard refuses. Prints what was overridden as warnings and records it in the note. |

```
$ tk close nw-5c46 --reason done -m "SSE reconnect shipped"
Updated nw-5c46 -> closed
Note: Closed: done - SSE reconnect shipped
Now ready: nw-7a21
Last open child of nw-0a11 closed - consider closing nw-0a11
```

Guards (all violations are reported at once, nothing is written, exit 1):

- open blockers - the work cannot be finished yet;
- open children - close or detach them first;
- for `wontdo`, `duplicate` and `superseded`: open tickets that depend on this one. They would see the dependency as resolved although nothing was delivered; settle them first with `tk undep` / `tk dep`.

Note written through `tk super add-note`:

| Reason | First line |
|---|---|
| `done` | `Closed: done - <text>` |
| `wontdo` | `Closed: won't do - <text>` |
| `duplicate` | `Closed: duplicate of <ref>` (`- <text>` appended when `-m` is given) |
| `superseded` | `Closed: superseded by <ref>` (`- <text>` appended when `-m` is given) |

A forced close that overrode a guard adds a second line, for example `Forced: open blockers nw-1d09; open children nw-3c10`.

After the close the plugin prints `Now ready: <ids>` (or `Nothing became ready`) and, when the parent lost its last open child, a hint to close the parent. A ticket that is already closed prints `<id> is already closed` and exits 0 without a second note.

Exit codes: 0 closed or already closed; 1 guard refused, ticket or `--ref` not found / ambiguous, `--ref` is the ticket itself, `ticket-impact` missing, or a delegated built-in (`tk super add-note`, `tk super close`) failed; 2 usage error or no tickets directory.

Requires bash, POSIX awk and the `ticket-impact` plugin on `PATH` (the packages declare the dependency). It contains no graph logic: every fact comes from `tk impact --porcelain`, IDs are resolved by `tk super show`. Bypass: `tk super close <id>` runs the built-in. `tk status <id> closed` is not guarded; `tk lint --conventions` reports such a close as `close-note`.
