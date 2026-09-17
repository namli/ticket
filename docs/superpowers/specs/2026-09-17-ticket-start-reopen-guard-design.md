# ticket-start / ticket-reopen guards: design

Ticket: `tic-6rw0`. Date: 2026-09-17. Guard style decided in `tic-zmz1` (option A: plugins shadow the built-in names). Graph facts come from `tk impact --porcelain` (`tic-5lpp`, spec `2026-09-17-ticket-impact-design.md`). Conventions shared with the other guards: `2026-09-17-ticket-dep-guard-design.md` (`tic-mwhy`) and `2026-09-17-ticket-close-guard-design.md` (`tic-yxrw`), both on their own branches.

## Goal

The built-in `tk start` is `cmd_status "$1" in_progress`: it starts a ticket whose blockers are still open, and it "starts" a closed ticket, which is a reopen with no reason and no report. The built-in `tk reopen` is `cmd_status "$1" open`: it silently re-blocks every dependent, always sets `open` (work in progress has to be restored by hand with `tk status <id> in_progress`), demotes an `in_progress` ticket to `open`, and records no reason. The `managing-tk-tickets` skill compensates by hand: "`tk start` works on a blocked ticket - never do it", and the Reopening paragraph (`tk add-note <id> "Reopened: <reason>"`, `tk reopen <id>`, `tk blocked` -> report what went back).

Two plugins move those steps into the commands:

- `plugins/ticket-start` refuses to start a ticket with open blockers, and refuses a closed ticket outright;
- `plugins/ticket-reopen` requires a reason, writes the `Reopened:` note with the exact prefix, can restore `in_progress` in the same command, and reports which dependents went back to blocked.

An agent that types `tk start` / `tk reopen` from habit hits the guard, because plugin dispatch looks up `ticket-start` / `ticket-reopen` on `PATH` before the built-in.

## Non-goals

- No changes to the core `ticket` script.
- No guard for `tk status <id> in_progress|open`. `status` is not shadowed.
- No check for reopening a child of a closed parent. It is not a reason to refuse a reopen, and `tk lint` already reports it (`open-child-of-closed` warning).
- No report of dependents that were already blocked by something else (the `blocked` porcelain lines): their state does not change. `tk impact <id>` shows them before the reopen.
- No `target <full-id>` line in `tk impact --porcelain`; IDs are resolved through `tk super show`, as in `ticket-close`. `ticket-impact` stays at 1.0.0.
- No skill rewrite (`tic-x75b`) beyond the minimal edits listed under Documentation.
- The guard exists only where the plugins are on `PATH`. Failing loudly when they are missing is `tic-x75b`.

## CLI

```
tk start  <id> [--force]
tk reopen <id> -m <reason> [--in-progress] [--force]
```

`tk start`:

| Flag | Effect |
|---|---|
| `--force` | Start although the ticket has open blockers. Does NOT override the closed-ticket refusal. |
| `-h`, `--help` | Print usage on stdout, exit 0. |
| `--` | End of options. |

`tk reopen`:

| Flag | Effect |
|---|---|
| `-m <reason>` | Why the ticket is reopened. Required, must not be empty. Written as the `Reopened:` note. |
| `--in-progress` | Set status `in_progress` instead of `open`. |
| `--force` | With `--in-progress`: reopen although the ticket has open blockers. Without `--in-progress` there is nothing to override and the flag has no effect. |
| `-h`, `--help` | Print usage on stdout, exit 0. |
| `--` | End of options. |

Flags may appear before or after `<id>`. Exactly one positional argument is required.

Exit codes (same scheme as `ticket-impact`, `ticket-dep`, `ticket-close`):

| Code | Meaning |
|---|---|
| 0 | Status changed, or there was nothing to change (`start` on an `in_progress` ticket, `reopen` on a ticket that is not closed). |
| 1 | A guard refused; `<id>` not found or ambiguous; `ticket-impact` is not on `PATH`; a delegated built-in failed. |
| 2 | Usage error: unknown flag, missing or extra `<id>`, `reopen` without `-m` or with an empty one, `-m` without a value; no tickets directory (`TICKETS_DIR` unset or not a directory); or the plugin was run directly instead of through `tk` (`TK_SCRIPT` unset, as in `ticket-dep`). Message and usage on stderr. |

## Behaviour

### Shared steps

Both plugins begin the same way:

1. Parse and validate arguments (exit 2 on any usage error; nothing is resolved or read before this passes).
2. Resolve `<id>` by asking core instead of copying its find block:

   ```bash
   resolve_id() {
       local out
       out=$("$TK_SCRIPT" super show "$1") || return 1
       awk '/^id:/ && !done { print $2; done = 1 }' <<< "$out"
   }
   ```

   Exact and partial IDs behave exactly as everywhere else, and core's error texts (`Error: ticket '<id>' not found`, `Error: ambiguous ID '<id>' matches multiple tickets`) reach stderr unchanged, exit 1. The output is captured before it is parsed and awk reads to the end of its input, so `set -o pipefail` never sees a SIGPIPE. All later steps and all output use the full ID.
3. `ticket-impact` must be reachable: `command -v ticket-impact || command -v tk-impact`. Otherwise

   ```
   Error: tk start needs the ticket-impact plugin on PATH
   Use 'tk super start' to bypass the guard
   ```

   (`tk reopen` / `tk super reopen` in the other plugin), stderr, exit 1.
4. `facts=$("$TK_SCRIPT" impact --porcelain "$id") || exit $?`. One call, taken BEFORE any write. Lines are matched on the first word; unknown kinds are ignored (the porcelain consumer contract). Used facts: `status <status>` (the target's real status), `blocker <id>` (the target's deps that are not closed, dangling IDs included - independent of the target's status), and for `reopen` the `ready <id>` lines, which on a closed target are exactly the dependents a reopen re-blocks.

The plugins contain no graph logic and never edit a ticket file: every write goes through `"$TK_SCRIPT" super start|status|add-note`.

### start

After the shared steps, by the `status` fact:

1. `closed`: refuse, whatever the flags.

   ```
   Error: tic-a is closed - use 'tk reopen tic-a -m <reason> --in-progress'
   ```

   stderr, exit 1, no file touched. `--force` does not override it and the message does not name `tk super start`: a forced start of a closed ticket is exactly the note-less reopen this ticket removes. `tk super start` still bypasses the plugin, as `super` does for every command; the refusal just does not advertise it.
2. `in_progress`: print `tic-a is already in progress`, exit 0. No guard, no note - nothing changed.
3. Any other status (`open`, missing, unknown) with at least one `blocker` line:
   - without `--force`, on stderr, exit 1, no file touched:

     ```
     Error: tic-a has open blockers: tic-b, tic-c
     Use --force to start anyway, or 'tk super start' to bypass the guard
     ```

   - with `--force`: `Warning: starting tic-a with open blockers: tic-b, tic-c` on stderr, then the note `Forced start: open blockers tic-b, tic-c` via `super add-note` (built-in output suppressed, reported on stdout as `Note: Forced start: open blockers tic-b, tic-c`), then step 4. The note is the trace of the override, as the `Forced:` line is in `ticket-close`. If `add-note` fails, exit 1 before the status changes.
4. `"$TK_SCRIPT" super start "$id"` - prints the built-in's `Updated tic-a -> in_progress`. A failure exits 1 with the built-in's message; after a forced note: `Error: note written but tk super start failed`.

Stdout order on a forced start: `Updated ...`, then `Note: ...` (the order `ticket-close` uses), although the note is written first. `--force` on a ticket without blockers writes no note.

Blockers are listed in porcelain order (sorted by ID), joined with `, `.

### reopen

After the shared steps:

1. `status` is not `closed`: print `tic-a is not closed (status: open) - nothing to reopen` (the real status in the parentheses; `unknown` when the `status` fact is empty), exit 0. No note, no guard, no report. This also stops the built-in's demotion of an `in_progress` ticket to `open`. It applies with `--in-progress` too: starting an open ticket is `tk start`'s job.
2. Guard, only with `--in-progress`: at least one `blocker` line means the ticket would be in progress while blocked - the case `tk start` refuses.
   - without `--force`, on stderr, exit 1, no file touched:

     ```
     Error: tic-a has open blockers: tic-b, tic-c
     Use --force to reopen as in_progress anyway, or reopen without --in-progress
     ```

   - with `--force`: `Warning: reopening tic-a as in_progress with open blockers: tic-b, tic-c` on stderr, and the note gets a second line (below).

   A plain reopen (status `open`) is never refused: an open ticket with open blockers is simply blocked.
3. Note, then status (the order the ticket prescribes):

   ```bash
   "$TK_SCRIPT" super add-note "$id" "$note" >/dev/null
   "$TK_SCRIPT" super status "$id" "$new_status"     # open | in_progress
   ```

   A failure of either exits 1 with the built-in's message; if `add-note` succeeded and `status` failed, the note stays and the error says so (`Error: note written but tk super status failed`). On success stdout shows, in this order, the built-in's `Updated <id> -> open` (or `-> in_progress`) and `Note: <first line of the note>`.
4. Report, from the `ready` facts of shared step 4: `Re-blocked: tic-e, tic-f` (porcelain order), or `Nothing was re-blocked`.

Note text: first line `Reopened: <reason>` - the prefix the skill prescribes. A forced reopen that overrode the blocker guard appends a second line to the same note:

```
Reopened: parser regression in nested lists
Forced: open blockers tic-b, tic-c
```

`--force` with no violation (no `--in-progress`, or no open blockers) writes no `Forced:` line.

### Examples

```
$ tk start tic-a
Error: tic-a has open blockers: tic-b
Use --force to start anyway, or 'tk super start' to bypass the guard

$ tk reopen tic-a -m "parser regression in nested lists"
Updated tic-a -> open
Note: Reopened: parser regression in nested lists
Re-blocked: tic-e
```

## Architecture

Two files, each self-contained:

```bash
#!/usr/bin/env bash
# tk-plugin: Guarded start: refuse blocked and closed tickets
# tk-plugin-version: 1.0.0
```

```bash
#!/usr/bin/env bash
# tk-plugin: Guarded reopen: record the reason, report re-blocked dependents
# tk-plugin-version: 1.0.0
```

Two files rather than one file plus a symlink (the `ticket-dep` / `ticket-undep` arrangement): the CLIs share only the blocker guard, each command gets its own `tk help` description, its own version and its own package. The price is that two small helpers are repeated in each file (and once more in `ticket-close`); they are short and have no logic of their own.

| Function | In | Job |
|---|---|---|
| `usage` | both | Usage text. |
| `resolve_id <id>` | both | Full ID on stdout via `tk super show`, or core's error and return 1. |
| `facts_of <kind>` | both | The IDs (second field) of the porcelain lines of one kind, joined with `, `. |

Dependencies: bash, POSIX awk, the `ticket-impact` plugin. No `rg`, no `jq`, no `find`.

## Testing

New `features/ticket_start_guard.feature` and `features/ticket_reopen_guard.feature`, existing step definitions only (absence of a note is asserted with `ticket show` + `the output should not contain`, as in the `ticket-close` spec).

`ticket_start_guard.feature`:

| Area | Scenarios |
|---|---|
| Guard | open blocker -> exit 1, status still `open`, message lists the blocker and names `--force` and `tk super start`; two blockers listed in ID order; `in_progress` blocker refuses too; dangling dep refuses; closed blocker does not refuse; no deps -> starts |
| Force | `--force` starts despite a blocker, prints `Warning:` on stderr, writes the `Forced start: open blockers ...` note; `--force` without blockers writes no note |
| Closed | closed ticket -> exit 1, status still `closed`, message names `tk reopen ... --in-progress`; the same with `--force` |
| Already started | `in_progress` ticket -> `is already in progress`, exit 0, even with an open blocker |
| Usage | no ID, two IDs, unknown flag -> exit 2, status unchanged; `--force` before the ID; `--help` exits 0 |
| IDs | partial ID; unknown ID -> core's error text, exit 1; ambiguous ID -> exit 1 |
| Bypass | `tk super start <id>` starts a blocked ticket |

`ticket_reopen_guard.feature`:

| Area | Scenarios |
|---|---|
| Reason | without `-m` -> exit 2, status still `closed`, no note; empty `-m` -> exit 2; `-m` as the last argument without a value -> exit 2 |
| Note and status | `-m` writes exactly `Reopened: <reason>` and sets `open`; `--in-progress` sets `in_progress`; stdout order `Updated`, `Note:`, report |
| Report | a dependent whose only open blocker is the target is listed under `Re-blocked:`; a dependent also blocked by another open ticket is not listed; a closed dependent is not listed; `Nothing was re-blocked` |
| In-progress guard | `--in-progress` with an open blocker -> exit 1, status still `closed`, no note, message names `--force`; `--force` overrides, prints `Warning:`, note has the `Forced: open blockers ...` line; plain reopen with an open blocker succeeds with no `Forced:` line; `--force` without violation writes no `Forced:` line |
| Not closed | `open` ticket -> `is not closed (status: open)`, exit 0, no note; `in_progress` ticket stays `in_progress`, no note |
| Usage | no ID, two IDs, unknown flag -> exit 2; flags before the ID; `--help` exits 0 |
| IDs | partial ID (note and report use the full ID); unknown ID -> core's error text, exit 1; ambiguous ID -> exit 1 |
| Bypass | `tk super reopen <id>` reopens with no note |

The "`ticket-impact` missing" branch cannot be expressed with the existing steps (the suite puts `plugins/` on `PATH`); it is checked by hand for both plugins with a `PATH` that holds only a copy of the plugin, and the command and its output are recorded in the plan.

`features/ticket_status.feature`: "Start a ticket" (`ticket start test-0001`) and "Reopen a ticket" (`ticket reopen test-0001`) switch to `ticket super start` / `ticket super reopen`. They test core behaviour and would otherwise reach the guards (the reopen one would fail on the missing `-m`). This follows the rule set in the `ticket-dep` spec: core scenarios of a shadowed command go through `super`.

`make test` must pass; the two new features are also run with busybox awk first in `PATH`.

## Documentation and packaging

- `README.md`: `start` and `reopen` lines under "Official plugins" in the usage block (the core `start <id>` / `reopen <id>` lines stay - they document the built-ins); the official-plugins paragraph mentions `ticket-start` and `ticket-reopen` and that both need `ticket-impact`.
- `plugins/README.md`: a `ticket-start` and a `ticket-reopen` section (CLI, flags, exit codes, guards, note formats, report, bypass, dependency on `ticket-impact`).
- `CHANGELOG.md`: two `### Plugins` entries, `ticket-start 1.0.0` and `ticket-reopen 1.0.0`.
- NOT added to `pkg/extras.txt` (new plugins, not core extractions).
- Packages: both depend on `ticket-impact`. `scripts/publish-aur.sh` gets `start|reopen) extra_deps="'ticket-impact'" ;;` in its existing `case`; `scripts/publish-homebrew.sh` gets the same kind of `case` emitting an extra `depends_on "ticket-impact"` line in the plugin formula. The `tic-yxrw` branch adds the same for `close`; whichever merges second folds the names into one `case` arm.
- Skill, minimal edits only so the skill does not contradict the tools until `tic-x75b`. In `skills/managing-tk-tickets/SKILL.md`: the two "tk facts that bite" lines about `tk reopen` and `tk start`, Closing step 6 ("Commit abandoned" -> `tk reopen <id> -m "commit abandoned" --in-progress`) and the **Reopening** paragraph (-> `tk reopen <id> -m "<reason>"`, which reports what went back). In `skills/managing-tk-tickets/editing.md`: the "Closed tickets are not rewritten" line. Each keeps the manual `tk add-note` + `tk super reopen` / `tk status` as the fallback when the plugins are not installed. `~/.claude/skills/managing-tk-tickets` is a symlink into the main checkout, so the installed copy follows on merge.

## Merge note

The `tic-mwhy` (`ticket-dep`) and `tic-yxrw` (`ticket-close`) branches edit `README.md`, `plugins/README.md`, `CHANGELOG.md`, `SKILL.md`, the publish scripts and `features/ticket_status.feature` in the same places. Whichever branch merges later resolves plain textual conflicts; there is no semantic overlap.
