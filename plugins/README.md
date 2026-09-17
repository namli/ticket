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

## ticket-lint

`tk lint [--conventions] [--strict]` checks every ticket in `.tickets/` in one pass and prints one finding per line, sorted by file and line:

```
.tickets/nw-5c46.md:4: error: depends on itself [self-dep]
.tickets/nw-7a21.md:3: warning: in_progress but blocked by open nw-5c46 [blocked-in-progress]
```

The format is the one compilers use, so paths are clickable in terminals and editors and work with GitHub problem matchers or reviewdog (`-efm="%f:%l: %m"`). A summary (`2 errors, 1 warning`) goes to stderr; a clean run prints nothing.

| Rule | Level | Meaning |
|---|---|---|
| `id-mismatch` | error | `id:` is missing or differs from the file name |
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

Exit codes: `0` no errors, `1` errors (or warnings with `--strict`), `2` unknown option or no `.tickets` directory.

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
