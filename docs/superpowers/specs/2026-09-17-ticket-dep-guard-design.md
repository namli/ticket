# ticket-dep / ticket-undep guards: design

Ticket: `tic-mwhy`. Date: 2026-09-17. Guard style decided in `tic-zmz1` (option A: plugins shadow the built-in names).

## Goal

`tk dep` accepts `tk dep A A` and dependency cycles, its "already exists" check is a substring match on the `deps:` line, and neither `tk dep` nor `tk undep` records why the graph changed. The `managing-tk-tickets` skill compensates with manual steps: run `tk dep cycle`, then `tk add-note <blocked> "Blocked by <id>: <reason>"`. The guards move those steps into the commands themselves:

- `tk dep` refuses a self-dependency and any edge that would close a cycle, and writes the `Blocked by` note.
- `tk undep` writes a `No longer blocked by` note.
- Both finish with one line saying whether the ticket is now ready or blocked.

An agent that types `tk dep` from habit hits the guard, because plugin dispatch (`ticket`, main dispatch) looks up `ticket-dep` on `PATH` before the built-in.

## Non-goals

- No changes to the core `ticket` script. The substring checks in `cmd_dep` / `cmd_undep` stay; the plugin checks exactly before delegating and verifies afterwards.
- No `--force`. A self-dependency and a cycle are never legitimate; the only bypass is `tk super dep` / `tk super undep`, and refusal messages name it.
- No fix for `tic-seki` (`tk dep cycle` false positives). The guard does not call `tk dep cycle`.
- No guard for `link` / `unlink`, no `redep` (`tic-o862`), no skill rewrite (`tic-x75b`) beyond the minimal edits listed under Documentation.
- The guard exists only where the plugins are on `PATH`. Failing loudly when they are missing is `tic-x75b`.

## CLI

```
tk dep tree [--full] <id>
tk dep cycle
tk dep   <id> <dep-id> (--reason <text> | --no-note)
tk undep <id> <dep-id> (--reason <text> | --no-note)
```

`tk dep tree ...` and `tk dep cycle` are passed through unchanged: `exec "$TK_SCRIPT" super dep "$@"`.

| Flag | Effect |
|---|---|
| `--reason <text>`, `--reason=<text>` | Reason for the change, written as a note on `<id>`. Required unless `--no-note`. Must not be empty. |
| `--no-note` | Change the dependency without writing a note. Mutually exclusive with `--reason`. |
| `-h`, `--help` | Print usage on stdout, exit 0. |
| `--` | End of options. |

Flags may appear before, between or after the two IDs. Exactly two positional arguments are required.

Exit codes:

| Code | Meaning |
|---|---|
| 0 | Dependency added / removed, or `dep` found it already present. |
| 1 | Guard refused (self-dependency, cycle), ticket not found or ambiguous, `undep` of a dependency that is not there, a delegated built-in failed, or the post-check failed. |
| 2 | Usage error: unknown flag, wrong number of IDs, neither `--reason` nor `--no-note`, both of them, empty reason; or no tickets directory (`TICKETS_DIR` unset or not a directory). Message and usage on stderr. |

## Behaviour

### ID resolution

Both IDs are resolved the way `ticket_path` in core does it: trim whitespace, exact file `<id>.md`, otherwise a unique `*<id>*.md` match. Error texts are the same as core's (`Error: ticket '<id>' not found`, `Error: ambiguous ID '<id>' matches multiple tickets`), on stderr, exit 1. All later steps and all output use the full IDs.

### dep

1. Resolve `<id>` and `<dep-id>`.
2. `<id>` equals `<dep-id>`: `Error: <id> cannot depend on itself`, exit 1.
3. `<dep-id>` is already an element of `<id>`'s `deps` array (exact element comparison): print `Dependency already exists`, print the state line, exit 0. No note is written: nothing changed.
4. Cycle check. One awk pass loads the `deps` of every ticket, whatever its status - closed tickets count as edges, as in `ticket-lint`'s `dep-cycle` rule, because a closed ticket can be reopened. Walk the `deps` edges starting at `<dep-id>` (iterative, visited set, parent pointers). If `<id>` is reachable, refuse:

   ```
   Error: tic-a -> tic-b would create a cycle: tic-a -> tic-b -> tic-c -> tic-a
   Use 'tk super dep' to bypass the guard
   ```

   stderr, exit 1, no file touched. The printed path is the new edge followed by the existing path from `<dep-id>` back to `<id>`.
5. `"$TK_SCRIPT" super dep <id> <dep-id>`, output captured.
6. Post-check: `<dep-id>` must now be an exact element of `<id>`'s `deps`. If it is, print the captured output (`Added dependency: <id> -> <dep-id>`). If not - core's substring check answered "Dependency already exists" because `<dep-id>` is a substring of another dependency - print `Error: tk super dep did not add <dep-id> to <id> (core matched it as a substring of an existing dependency)` on stderr, exit 1, no note. The plugin never edits ticket files itself, so it reports this core bug instead of working around it.
7. Unless `--no-note`: `"$TK_SCRIPT" super add-note <id> "Blocked by <dep-id>: <text>"`. The built-in's `Note added to ...` line is replaced by `Note: Blocked by <dep-id>: <text>`.
8. Print the state line.

### undep

1. Resolve both IDs.
2. `<dep-id>` is not an exact element of `<id>`'s `deps`: print `Dependency not found`, exit 1, no note.
3. `"$TK_SCRIPT" super undep <id> <dep-id>`, output captured.
4. Post-check: `<dep-id>` must no longer be an element of `deps`. If so, print the captured output (`Removed dependency: <id> -/-> <dep-id>`); otherwise `Error: tk super undep did not remove <dep-id> from <id>` on stderr, exit 1, no note.
5. Unless `--no-note`: note `No longer blocked by <dep-id>: <text>`, reported as `Note: No longer blocked by <dep-id>: <text>`.
6. Print the state line.

### State line

Last line of stdout, computed from `<id>`'s file after the change:

| Condition | Line |
|---|---|
| `<id>` has status `closed` | `<id> is closed` |
| every dependency is closed, or there are none | `<id> is ready` |
| otherwise | `<id> is blocked by: <dep> [<status>], <dep> [<status>]` - the non-closed dependencies in `deps` order; a dependency whose file is missing is listed as `[missing]` |

Example:

```
$ tk dep tic-a tic-b --reason "needs the parser from tic-b"
Added dependency: tic-a -> tic-b
Note: Blocked by tic-b: needs the parser from tic-b
tic-a is blocked by: tic-b [open]
```

## Architecture

One file, `plugins/ticket-dep`, plus the symlink `plugins/ticket-undep -> ticket-dep` - the same arrangement as `ticket-list -> ticket-ls`. `scripts/publish-homebrew.sh` and `scripts/publish-aur.sh` already install symlinks together with their target, so one package `ticket-dep` ships both commands. The mode comes from the invoked name: strip the directory and the `tk-` / `ticket-` prefix from `$0`; `undep` selects undep mode, anything else dep mode.

```bash
#!/usr/bin/env bash
# tk-plugin: Guarded dep/undep: reject self-deps and cycles, record the reason
# tk-plugin-version: 1.0.0
```

`tk help` reads the description from the file, so `dep` and `undep` show the same line; it is worded for both.

Shell functions, each with one job:

| Function | Job |
|---|---|
| `usage` | Usage text for the current mode. |
| `resolve_id <id>` | Full ID on stdout, or core's error text and return 1. |
| `deps_of <id>` | The `deps` array of one ticket, one ID per line (front matter only, `gsub(/[][]/, "")` - POSIX bracket expression, see `tic-xj6g`). |
| `has_dep <id> <dep-id>` | Exact element test on `deps_of`. |
| `cycle_path <id> <dep-id>` | The awk walk; prints the cycle path and returns 0 when `<id>` is reachable from `<dep-id>`, returns 1 otherwise. |
| `write_note <id> <text>` | `super add-note`, built-in output suppressed, prints `Note: <text>`. |
| `state_line <id>` | The state line. |

Dependencies: bash, POSIX awk, `find`. No `rg`, no `jq`. Writes happen only through `"$TK_SCRIPT" super dep|undep|add-note`; the plugin itself never edits a ticket file.

## Testing

New `features/ticket_dep_guard.feature`; existing step definitions are enough (`should have "<id>" in deps`, `should not have ... in deps`, `should contain`, `the exit code should be`, `the error output should contain`, `the output line N should contain`).

| Area | Scenarios |
|---|---|
| Self-dependency | rejected with exit 1; `deps` unchanged; no note; message names `tk super dep` |
| Cycles | 2-node and 3-node cycle rejected, `deps` unchanged, no `Blocked by` note; cycle through a closed ticket rejected; error shows the path; a diamond (A->B, A->C, B->D, then C->D) is not a cycle and is accepted |
| Notes | `dep --reason` writes exactly `Blocked by <dep-id>: <text>`; `undep --reason` writes exactly `No longer blocked by <dep-id>: <text>`; `--reason=<text>` form; `--no-note` changes `deps` and writes no note |
| Usage | missing `--reason` -> exit 2, `deps` unchanged; `--reason` with `--no-note` -> exit 2; empty reason -> exit 2; unknown flag -> exit 2; one ID only -> exit 2 |
| Existing state | duplicate dep -> `Dependency already exists`, exit 0, no second note; undep of an absent dep -> `Dependency not found`, exit 1, no note |
| Exact matching | ticket `x` has deps `[abc-0012]` and ticket `abc-001` exists: `tk dep x abc-001 --reason ...` passes the exact pre-check, core answers "already exists" by substring, the post-check fails -> exit 1 with the `did not add` error, no note, `deps` unchanged |
| State line | `is ready` after undep of the last open blocker; `is blocked by:` listing every non-closed dep with status; dep on a closed ticket -> `is ready`; closed `<id>` -> `is closed` |
| IDs | partial IDs resolve; nonexistent ID -> core's error text, exit 1 |
| Pass-through | `tk dep tree <id>` and `tk dep cycle` work through the plugin |
| Bypass | `tk super dep A A` still succeeds (built-in untouched) |

Existing scenarios that exercise the built-in with `ticket dep <a> <b>` / `ticket undep <a> <b>` switch to `ticket super dep` / `ticket super undep`: six in `features/ticket_dependencies.feature`, one in `features/id_resolution.feature`, one in `features/ticket_directory.feature`. They test core behaviour, and `features/environment.py` puts `plugins/` on `PATH` for the whole suite, so without `super` they would reach the guard. The `dep tree` scenarios stay as they are and double as pass-through coverage. This sets the rule for the other guard plugins (`tic-yxrw`, `tic-6rw0`): core scenarios of a shadowed command go through `super`.

`make test` must pass; the new feature is also run with busybox awk first in `PATH`.

## Documentation and packaging

- `README.md`: `dep` / `undep` lines under "Official plugins" in the usage block; official-plugins paragraph.
- `plugins/README.md`: a `ticket-dep` section (CLI, flags, exit codes, state line, bypass, the symlink).
- `CHANGELOG.md`: `### Plugins` entry, `ticket-dep 1.0.0`, mentioning the `ticket-undep` symlink.
- NOT added to `pkg/extras.txt` (new plugin, not a core extraction).
- Skill, minimal edits only so the skill does not contradict the tool until `tic-x75b`: `skills/managing-tk-tickets/SKILL.md` Creating step 4 and the "Dep without a reason" row of Common mistakes, and step 3 of `skills/managing-tk-tickets/editing.md`, switch to `tk dep <blocked> <blocker> --reason "<why>"` / `tk undep ... --reason "<why>"`, keeping the manual `tk add-note` as the fallback when the plugin is not installed.
