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

## ticket-dep (and ticket-undep)

`plugins/ticket-dep` shadows the built-in `tk dep`; `plugins/ticket-undep` is a symlink to it and shadows `tk undep`. One package, `ticket-dep`, installs both.

```
tk dep   <id> <dep-id> (--reason <text> | --no-note)
tk undep <id> <dep-id> (--reason <text> | --no-note)
tk dep tree [--full] <id>      unchanged, passed to the built-in
tk dep cycle                   unchanged, passed to the built-in
```

```
$ tk dep nw-5c46 nw-7a21 --reason "needs the session store"
Added dependency: nw-5c46 -> nw-7a21
Note: Blocked by nw-7a21: needs the session store
nw-5c46 is blocked by: nw-7a21 [open]
```

What the guard adds to the built-in:

- `tk dep A A` is refused.
- A dependency that would close a cycle is refused and the cycle is shown (`A -> B -> C -> A`). Closed tickets count as edges, as in `tk lint`. The check does not rely on `tk dep cycle`.
- "Already exists" / "not found" compare whole IDs; the built-in matches substrings of the `deps:` line. If the built-in refuses a dependency because of that, the plugin reports it (exit 1) instead of printing a false "already exists".
- `tk undep` refuses (exit 1) when the built-in would damage another dependency: it removes the ID as an unanchored pattern, so removing `abc-001` next to `abc-0012`, or `a.b-0001` next to `axb-0001`, would corrupt `deps`. Such a dependency has to be removed by editing the ticket file. After every `undep` the plugin also checks that the other dependencies are unchanged.
- `--reason <text>` is required and is written as a note on `<id>`: `Blocked by <dep-id>: <text>` for `dep`, `No longer blocked by <dep-id>: <text>` for `undep`. `--no-note` skips the note.
- The last output line says where the ticket stands: `<id> is ready`, `<id> is blocked by: <dep> [<status>], ...` or `<id> is closed`.

There is no `--force`: a self-dependency or a cycle is never legitimate. `tk super dep` / `tk super undep` run the built-in without the guard.

Exit codes: `0` done (or the dependency was already there), `1` refused, ticket not found, `undep` of a dependency that is not there, or the built-in failed, `2` usage error or no `.tickets` directory found.

Requires only bash, POSIX awk and `find`. The plugin never edits ticket files itself; every write goes through `tk super dep|undep|add-note`.

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

## ticket-start

`tk start <id> [--force]` shadows the built-in `tk start`, which starts anything - including a ticket whose blockers are still open. It accepts one full or partial ID; flags may come before or after it.

| Ticket | Result |
|---|---|
| has open blockers (any dependency that is not `closed`, dangling IDs included) | refused, exit 1; `--force` starts it anyway, prints a `Warning:` and writes the note `Forced start: open blockers <ids>` |
| is `closed` | always refused, exit 1, also with `--force`: starting a closed ticket is a reopen without a reason - use `tk reopen <id> -m <reason> --in-progress` |
| is `in_progress` | `<id> is already in progress`, exit 0, nothing changes |
| otherwise | `Updated <id> -> in_progress` |

```
$ tk start nw-5c46
Error: nw-5c46 has open blockers: nw-1d09
Use --force to start anyway, or 'tk super start' to bypass the guard
```

Exit codes: 0 started or already in progress, 1 refused / ticket not found or ambiguous ID or an `id:` field that does not match the file name / `ticket-impact` missing, 2 usage error (including an empty ID) or no tickets directory.

The guard reads its facts from `tk impact --porcelain` and changes the ticket only through `tk super start` and `tk super add-note`. `tk super start <id>` runs the unguarded built-in.

Requires bash, POSIX awk and the `ticket-impact` plugin.

## ticket-reopen

`tk reopen <id> -m <reason> [--in-progress] [--force]` shadows the built-in `tk reopen`, which silently re-blocks dependents, always sets `open` and records nothing.

| Flag | Effect |
|---|---|
| `-m <reason>` | Required, not empty. Written as the note `Reopened: <reason>`. |
| `--in-progress` | Set `in_progress` instead of `open`. Refused (exit 1) when the ticket has open blockers - the case `tk start` refuses. |
| `--force` | With `--in-progress`: reopen despite open blockers; prints a `Warning:` and adds a second note line `Forced: open blockers <ids>`. |

```
$ tk reopen nw-5c46 -m "reconnect loop under packet loss"
Updated nw-5c46 -> open
Note: Reopened: reconnect loop under packet loss
Re-blocked: nw-7a21
```

`Re-blocked:` lists the dependents whose only open blocker is now the reopened ticket, i.e. the ones that leave `tk ready`; dependents that were already blocked by something else are not listed. With none it prints `Nothing was re-blocked`. A ticket that is not closed is left alone: `<id> is not closed (status: <status>) - nothing to reopen`, exit 0, no note - so an `in_progress` ticket is never demoted to `open`. A plain reopen (without `--in-progress`) is never refused.

Exit codes: 0 reopened or nothing to reopen, 1 refused / ticket not found or ambiguous ID or an `id:` field that does not match the file name / `ticket-impact` missing, 2 usage error (including a missing or empty `-m`) (including an empty ID) or no tickets directory.

The facts come from one `tk impact --porcelain` call taken while the ticket is still closed; the note and the status go through `tk super add-note` and `tk super status`. `tk super reopen <id>` runs the unguarded built-in.

Requires bash, POSIX awk and the `ticket-impact` plugin.

## ticket-close

`ticket-close` shadows the built-in `tk close`. The built-in closes anything and records nothing; because ANY closed dependency counts as resolved, a wrong close silently moves dependents to `tk ready`. The guard refuses unsafe closes, records the resolution and reports the effect.

```
tk close <id> --reason done|wontdo|duplicate|superseded [-m <text>] [--ref <id>] [--force]
```

| Flag | Effect |
|---|---|
| `--reason <r>`, `--reason=<r>` | Resolution, required. |
| `-m <text>` | Free text for the note. Required for `done` and `wontdo`, optional for `duplicate` and `superseded`. Must be a single line. |
| `--ref <id>`, `--ref=<id>` | The ticket this one duplicates / is superseded by (full or partial ID). Required for `duplicate` and `superseded`, rejected otherwise. |
| `--force` | Close although a guard refuses. Prints what was overridden as warnings and records it in the note. |
| `-h`, `--help` | Print usage, exit 0. |
| `--` | End of options. |

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

Exit codes: 0 closed or already closed; 1 guard refused, ticket or `--ref` not found / ambiguous, `--ref` is the ticket itself, file name and id field of a ticket differ, `ticket-impact` missing, or a delegated built-in (`tk super add-note`, `tk super close`) failed; 2 usage error, no tickets directory, or `TK_SCRIPT` unset (the plugin was not started through `tk`).

Requires bash, POSIX awk and the `ticket-impact` plugin on `PATH` (the packages declare the dependency). It contains no graph logic: every fact comes from `tk impact --porcelain`, IDs are resolved by `tk super show`. Bypass: `tk super close <id>` runs the built-in. `tk status <id> closed` is not guarded; `tk lint --conventions` reports such a close as `close-note`.
