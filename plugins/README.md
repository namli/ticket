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
