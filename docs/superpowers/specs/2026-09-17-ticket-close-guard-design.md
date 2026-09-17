# ticket-close guard: design

Ticket: `tic-yxrw`. Date: 2026-09-17. Guard style decided in `tic-zmz1` (option A: plugins shadow the built-in names). Graph facts come from `tk impact --porcelain` (`tic-5lpp`, spec `2026-09-17-ticket-impact-design.md`).

## Goal

The built-in `tk close` is `cmd_status "$1" closed`: it closes a ticket that still has open blockers, closes a parent with open children, and records no reason. Because ANY closed blocker counts as resolved, a wrong close silently moves dependents to `tk ready`. The `managing-tk-tickets` skill compensates by hand: check `tk show` (Closing step 1), write a `Closed: <resolution>` note (step 4), run `tk ready` and report what was unblocked (step 5), and settle every dependent before a won't-do close.

`plugins/ticket-close` moves those steps into the command:

- it refuses to close a ticket with open blockers or open children;
- it refuses a won't-do / duplicate / superseded close while open tickets still depend on the target;
- it requires a resolution and writes the `Closed:` note with the exact prefix;
- it reports which tickets became ready and whether the parent lost its last open child.

An agent that types `tk close` from habit hits the guard, because plugin dispatch looks up `ticket-close` on `PATH` before the built-in.

The plugin does NOT replace the skill's STOP AND ASK step: whether the work is really done stays a judgment call.

## Non-goals

- No changes to the core `ticket` script.
- No guard for `tk status <id> closed`. `status` is not shadowed; a close made that way has no `Closed:` note and is reported by `tk lint --conventions` (`close-note` rule).
- No `target <full-id>` line in `tk impact --porcelain` (the question deferred from `tic-5lpp`). It would resolve only the target, not `--ref`; both are resolved through `tk super show` instead (see ID resolution). `ticket-impact` stays at 1.0.0.
- No "still blocked" section in the report. `tk impact <id>` shows it before the close.
- No skill rewrite (`tic-x75b`) beyond the minimal edits listed under Documentation.
- The guard exists only where the plugins are on `PATH`. Failing loudly when they are missing is `tic-x75b`.

## CLI

```
tk close <id> --reason done|wontdo|duplicate|superseded [-m <text>] [--ref <id>] [--force]
```

| Flag | Effect |
|---|---|
| `--reason <r>`, `--reason=<r>` | Resolution. Required. One of `done`, `wontdo`, `duplicate`, `superseded`. |
| `-m <text>` | Free text for the note. Required and non-empty for `done` and `wontdo`; optional for `duplicate` and `superseded`. Must be a single line: a newline is a usage error. |
| `--ref <id>`, `--ref=<id>` | The ticket this one duplicates / is superseded by. Required for `duplicate` and `superseded`, rejected for `done` and `wontdo`. Partial IDs are accepted. |
| `--force` | Close although a guard would refuse. Overrides every guard at once; what was overridden is printed as warnings and recorded in the note. |
| `-h`, `--help` | Print usage on stdout, exit 0. |
| `--` | End of options. |

Flags may appear before or after `<id>`. Exactly one positional argument is required.

Exit codes (same scheme as `ticket-impact` and `ticket-dep`):

| Code | Meaning |
|---|---|
| 0 | Ticket closed, or it was already closed (nothing changed). |
| 1 | A guard refused; `<id>` or `--ref` not found or ambiguous; `--ref` resolves to the target itself; a ticket whose file name and `id` field differ, or without an `id` field; `ticket-impact` is not on `PATH`; a delegated built-in failed. |
| 2 | Usage error: unknown flag, missing or extra `<id>`, empty `<id>`, missing or invalid `--reason`, `done` / `wontdo` without `-m` or with an empty one, a newline in `-m`, `duplicate` / `superseded` without `--ref`, `--ref` with `done` / `wontdo`; or no tickets directory (`TICKETS_DIR` unset or not a directory); or `TK_SCRIPT` unset (the plugin was not started through `tk`). Message and usage on stderr. |

## Behaviour

### ID resolution

`resolve_id <id>` asks core instead of copying its find block:

```bash
resolve_id() {
    local input out id
    read -r input <<< "$1" || true
    out=$("$TK_SCRIPT" super show "$input") || return 1
    id=$(awk '
        NR == 1 && $0 != "---" { exit }
        NR > 1 && $0 == "---" { exit }
        /^id:/ { print $2; exit }
    ' <<< "$out")
    if [[ -z "$id" ]]; then
        echo "Error: ticket '$input' has no id field (run tk lint)" >&2
        return 1
    fi
    if [[ ! -f "$TICKETS_DIR/$id.md" || "$id" != *"$input"* ]] ||
       [[ -f "$TICKETS_DIR/$input.md" && "$id" != "$input" ]]; then
        echo "Error: ticket '$input': file name and id field differ (run tk lint)" >&2
        return 1
    fi
    echo "$id"
}
```

`tk super show` resolves through core's `ticket_path`, so exact and partial IDs behave exactly as everywhere else, and core's error texts (`Error: ticket '<id>' not found`, `Error: ambiguous ID '<id>' matches multiple tickets`) reach stderr unchanged, exit 1. The output is captured before it is parsed, and the awk program reads to the end of its input, so `set -o pipefail` never sees a SIGPIPE.

The `id:` field is read from the leading front matter only: line 1 of the captured output must be exactly `---`, and the scan stops at the next `---`. A line matching `id:` in the body, or in the computed sections `tk show` appends after the file content, is never seen - the awk program exits as soon as the front matter closes.

An empty result (no `id:` field found in the front matter) is refused: `Error: ticket '<input>' has no id field (run tk lint)`.

The result must also name the file core actually resolved, or it is refused: `Error: ticket '<input>': file name and id field differ (run tk lint)`, unless ALL of:

- `$TICKETS_DIR/$id.md` exists;
- `$id` contains `<input>` as a substring;
- if `$TICKETS_DIR/<input>.md` exists (the exact match core prefers), `$id` equals `<input>`.

This is sufficient because core resolves either the exact file `<input>.md` or the unique file matching `*<input>*.md`. In the exact case the id must equal the input. In the partial case, if `$id.md` exists and `$id` contains the input, then `$id.md` itself matches `*<input>*.md`, and since that match is unique it IS the file core resolved.

All later steps and all output use full IDs.

### Steps

1. Parse and validate arguments (exit 2 on any usage error; nothing is resolved or read before this passes).
2. Resolve `<id>`; resolve `--ref` when given. `--ref` equal to the target: `Error: <id> cannot be a duplicate of itself` / `... cannot be superseded by itself`, exit 1. The referenced ticket may have any status.
3. `ticket-impact` must be reachable: `command -v ticket-impact || command -v tk-impact`. Otherwise

   ```
   Error: tk close needs the ticket-impact plugin on PATH
   Use 'tk super close' to bypass the guard
   ```

   stderr, exit 1.
4. `facts=$("$TK_SCRIPT" impact --porcelain "$id") || exit $?`. One call, taken BEFORE the close: `tk impact` computes every fact as if the target were closed, so this is both the guard input and the forecast for the report. Lines are matched on the first word; unknown kinds are ignored (the porcelain consumer contract).
5. `status closed`: print `<id> is already closed`, exit 0. No note, no guard, no report - nothing changed.
6. Guards. All violations are collected, not only the first:

   | Violation | Source lines | Applies to |
   |---|---|---|
   | open blockers | `blocker <id>` | every reason |
   | open children | `child <id>` | every reason |
   | open dependents | `ready <id>` and `blocked <id> ...` (second field) | `wontdo`, `duplicate`, `superseded` |

   Open dependents are refused only for the non-`done` reasons: after such a close they would hold a dependency that counts as resolved although the work was never delivered. Both `ready` and `blocked` dependents count - a dependent still blocked by something else carries the same false edge.

   Without `--force`, on stderr, exit 1, no file touched:

   ```
   Error: tic-a has open blockers: tic-b, tic-c
   Error: tic-a has open children: tic-d
   Error: tic-a has open dependents that would see it as resolved: tic-e (settle them first: tk undep / tk dep)
   Use --force to close anyway, or 'tk super close' to bypass the guard
   ```

   Only the lines for actual violations are printed. With `--force` the same facts are printed as `Warning: closing tic-a with open blockers: tic-b, tic-c` (and likewise for children and dependents) on stderr, and the close proceeds.
7. Note, then close (the order the ticket prescribes; both go through core, the plugin never edits a ticket file):

   ```bash
   "$TK_SCRIPT" super add-note "$id" "$note" >/dev/null
   "$TK_SCRIPT" super close "$id"
   ```

   A failure of either exits 1 with the built-in's message; if `add-note` succeeded and `close` failed, the note stays and the error says so (`Error: note written but tk super close failed`). On success stdout shows, in this order, the built-in's `Updated <id> -> closed` and `Note: <first line of the note>` (the built-in's `Note added to ...` line is dropped).
8. Report, from the facts of step 4:
   - `Now ready: tic-e, tic-f` (the `ready` lines, in porcelain order), or `Nothing became ready`;
   - when a `last-child <parent>` line is present: `Last open child of <parent> closed - consider closing <parent>`.

### Note text

First line, by reason (`<text>` is `-m`, `<ref>` the resolved full ID):

| Reason | Note |
|---|---|
| `done` | `Closed: done - <text>` |
| `wontdo` | `Closed: won't do - <text>` |
| `duplicate` | `Closed: duplicate of <ref>` or `Closed: duplicate of <ref> - <text>` |
| `superseded` | `Closed: superseded by <ref>` or `Closed: superseded by <ref> - <text>` |

These are the prefixes the skill prescribes and `ticket-lint`'s `close-note` rule (`^Closed: `) recognises.

A forced close that overrode at least one guard appends a second line to the same note, naming only what was overridden, in the order blockers, children, dependents:

```
Closed: done - shipped
Forced: open blockers tic-b; open children tic-c
```

`--force` on a ticket with no violations writes no `Forced:` line.

### Example

```
$ tk close tic-a --reason done -m "guard plugin shipped"
Updated tic-a -> closed
Note: Closed: done - guard plugin shipped
Now ready: tic-e
Last open child of tic-p closed - consider closing tic-p
```

## Architecture

One file, `plugins/ticket-close`:

```bash
#!/usr/bin/env bash
# tk-plugin: Guarded close: refuse unsafe closes, record the reason, report what got unblocked
# tk-plugin-version: 1.0.0
```

Shell functions, each with one job:

| Function | Job |
|---|---|
| `usage` | Usage text. |
| `resolve_id <id>` | Full ID on stdout via `tk super show`, or core's error and return 1. |
| `die_usage <msg>` | `Error: <msg>` and the usage on stderr, exit 2. |
| `facts_of <kind>...` | The IDs (second field) of the porcelain lines of the given kinds, joined with `, `. |

The plugin contains no graph logic and no pass over the ticket files: every graph fact comes from `tk impact --porcelain`, every write goes through `"$TK_SCRIPT" super add-note|close`. Dependencies: bash, POSIX awk, the `ticket-impact` plugin. No `rg`, no `jq`.

## Testing

New `features/ticket_close_guard.feature`, existing step definitions only (no new step: `ticket-dep`'s branch adds one to the same file, and absence of a note can be asserted with `ticket show` + `the output should not contain`).

| Area | Scenarios |
|---|---|
| Guards | open blocker -> exit 1, status unchanged, no `Closed:` note, message names `--force` and `tk super close`; open child -> the same; blocker and child together -> both `Error:` lines; closed blocker / closed child do not refuse |
| Dependents | `wontdo` with an open dependent refused and the dependent listed; `duplicate` and `superseded` likewise; a dependent that is also blocked by another ticket still counts; `done` with open dependents is allowed; closed dependents do not refuse |
| Force | `--force` closes despite blocker + child, prints `Warning:` lines, note has the `Forced: open blockers ...; open children ...` line; `--force` without violations writes no `Forced:` line; a target with two blockers, a child AND a dependent at once records all three classes in one `Forced:` line |
| Notes | exact first line for each of the four reasons; `duplicate` / `superseded` with `-m` append ` - <text>`; `--ref` given as a partial ID is written as the full ID |
| Usage | missing `--reason`, invalid reason, `done` without `-m`, `wontdo` without `-m`, empty `-m`, a newline in `-m`, an empty or whitespace-only `<id>`, `duplicate` without `--ref`, `superseded` without `--ref`, `duplicate` with `--ref` and an empty `-m`, `--ref` with `done`, unknown flag, no ID, two IDs -> exit 2 and status unchanged; `--reason` / `-m` / `--ref` as the last argument (no following value); `--reason=<r>` form; flags before the ID; `--` ends options; no tickets directory; `--help` exits 0 |
| ID consistency | target or `--ref` resolves to a ticket whose file name and `id` field differ -> refused, both tickets left untouched; a ticket with no `id` field but a body line naming another ticket -> refused; a body line naming another ticket does not confuse a well-formed ticket's own id; an ID that is an exact prefix of another (`cl-1` / `cl-12`) closes only itself |
| IDs | partial target ID; unknown ID -> core's error text, exit 1; ambiguous ID -> exit 1; unknown `--ref` -> exit 1 and target still open; `--ref` equal to the target -> exit 1 |
| Already closed | `<id> is already closed`, exit 0, no second note; an `in_progress` target closes normally |
| Report | `Now ready:` lists the unblocked dependent and omits one still blocked by another ticket; `Nothing became ready`; parent hint when the last open child closes; no hint while a sibling is open |
| Bypass | `tk super close <id>` closes a blocked ticket with no note |

The "`ticket-impact` missing" branch cannot be expressed with the existing steps (the suite puts `plugins/` on `PATH`); it is checked by hand with a `PATH` that holds only a copy of `ticket-close`, and the command and its output are recorded in the plan.

`features/ticket_status.feature` ("Close a ticket") switches from `ticket close test-0001` to `ticket super close test-0001`: it tests core behaviour and would otherwise reach the guard. This follows the rule set in the `ticket-dep` spec: core scenarios of a shadowed command go through `super`.

`make test` must pass; the new feature is also run with busybox awk first in `PATH`.

## Documentation and packaging

- `README.md`: a `close` line under "Official plugins" in the usage block (the core `close <id>` line stays - it documents the built-in); official-plugins paragraph mentions `ticket-close` and that it needs `ticket-impact`.
- `plugins/README.md`: a `ticket-close` section (CLI, flags, exit codes, guards, note formats, report, bypass, dependency on `ticket-impact`).
- `CHANGELOG.md`: `### Plugins` entry, `ticket-close 1.0.0`.
- NOT added to `pkg/extras.txt` (new plugin, not a core extraction).
- Packages: `ticket-close` depends on `ticket-impact`. `scripts/publish-aur.sh` gets `close) extra_deps="'ticket-impact'"` in its existing `case`; `scripts/publish-homebrew.sh` gets the same kind of `case` emitting an extra `depends_on "ticket-impact"` line in the plugin formula.
- Skill, minimal edits only so the skill does not contradict the tool until `tic-x75b`: in `skills/managing-tk-tickets/SKILL.md` the "tk facts that bite" line about `tk close`, Closing step 4, the note-prefix line and the "Won't do / duplicate / superseded" paragraph switch to `tk close <id> --reason <r> -m "<text>" [--ref <id>]`, keeping the manual `tk add-note` + `tk super close` as the fallback when the plugin is not installed. `~/.claude/skills/managing-tk-tickets` is a symlink into the main checkout, so the installed copy follows on merge.

## Merge note

The `tic-mwhy` branch (`ticket-dep`) edits `README.md`, `plugins/README.md`, `CHANGELOG.md` and `SKILL.md` in the same places. Whichever branch merges second resolves plain textual conflicts; there is no semantic overlap.
