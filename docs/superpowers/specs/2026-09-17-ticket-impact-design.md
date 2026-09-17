# ticket-impact: design

Ticket: `tic-5lpp`. Date: 2026-09-17.

## Goal

Closing a ticket changes the graph: dependents may become ready, a parent may lose its last open child, and a close with open blockers or open children is usually a mistake. Today the `managing-tk-tickets` skill asks the agent to work this out by hand from `tk show`, `tk ready` and `tk blocked` (Closing steps 1, 3 and 5, and the "Won't do / duplicate / superseded" paragraph). `tk impact <id>` answers it in one read-only command, and its `--porcelain` mode is the single place where this graph logic lives, so `ticket-close` (`tic-yxrw`) and `ticket-reopen` (`tic-6rw0`) reuse it instead of duplicating it.

## Non-goals

- No changes to the core `ticket` script.
- No writes: impact never modifies a ticket.
- One ID per call, no JSON output, no transitive impact (see Computation).
- No `--ids-ready` flag. The ticket text names it; `--porcelain` replaces it because `ticket-close` also needs open blockers and open children, which a list of ready IDs cannot carry.
- No skill rewrite (`tic-x75b`).

## CLI

```
tk impact [--porcelain] <id>
```

| Argument | Effect |
|---|---|
| `<id>` | Exactly one ticket ID, full or partial. |
| `--porcelain` | Stable machine-readable output (see Output). May come before or after `<id>`. |
| `-h`, `--help` | Print usage on stdout, exit 0. |

Exit codes:

| Code | Meaning |
|---|---|
| 0 | Impact printed, including "no impact". |
| 1 | Ticket not found, or partial ID ambiguous. Message on stderr, same wording as `ticket-edit`: `Error: ticket '<id>' not found`, `Error: ambiguous ID '<id>' matches multiple tickets`. Also when no ticket carries the resolved ID in its `id:` field: `Error: no ticket with id <id> (file name and id field differ?)`. |
| 2 | Unknown flag, missing `<id>`, more than one `<id>`, or no tickets directory (`TICKETS_DIR` unset or not a directory). Usage or message on stderr. When run through `tk`, a `TICKETS_DIR` that is set but missing is rejected by the core dispatcher with exit 1 before the plugin starts. |

Partial IDs are resolved inside the plugin with the same `find "$TICKETS_DIR" -maxdepth 1 -name "*<id>*.md"` logic as `plugins/ticket-edit` (exact file name first, then a unique partial match). Plugins are standalone files, so the few lines are copied rather than parsed out of `tk super show`.

## Computation

One awk pass over `"$TICKETS_DIR"/*.md`, reading `id`, `status`, `deps`, `parent` from the front matter and the first `# ` heading as the title, the same way `cmd_show` and `cmd_ready` do. Ticket identity is the `id:` field, as in the core script; the target ID is the base name of the resolved file.

Every fact is computed **as if the target were closed**, whatever its real status. This gives one semantics for both consumers: before a close it is the forecast, on an already closed ticket it is what a reopen would undo.

| Fact | Rule |
|---|---|
| blocker | An ID in the target's `deps` whose status is not `closed`. A dangling ID (no such ticket) counts as a blocker, as in `cmd_ready`. |
| child | A ticket with `parent == target` and status not `closed`. |
| ready | A ticket with status not `closed` whose `deps` contain the target and whose other deps are all `closed`. |
| blocked | A ticket with status not `closed` whose `deps` contain the target and that has at least one other dep not `closed` (dangling IDs included). Carries the list of those other deps. |
| last-child | The target has a `parent`, that parent exists and is not `closed`, and no other ticket with the same `parent` has a status other than `closed`. |

Details:

- Only direct dependents are examined. If closing A makes B ready, a ticket C that depends on B is not reported: B is still open.
- The target never appears in its own lists: a self-dependency is not a blocker, a self-parent is not a child.
- A dependent that names the target twice in `deps` is reported once; duplicate IDs in a `blocked` list are collapsed.
- Closed dependents and closed children are ignored.
- Any status other than `closed` counts as open: `in_progress`, but also a missing or unknown status. `tk ready` and `tk blocked` list only `open` and `in_progress` tickets, so impact can name a ticket they do not show.
- IDs are compared as strings (`100` and `1e2` are different tickets). IDs and statuses are assumed to contain no whitespace and no commas, which holds for everything `tk` generates; the porcelain format relies on it.

## Output

### Porcelain

One fact per line, first word is the fact kind, fields separated by a single space:

```
status <status>
blocker <id>
child <id>
ready <id>
blocked <id> <dep>[,<dep>...]
last-child <parent-id>
```

```
$ tk impact --porcelain tic-zmz1
status open
ready tic-6rw0
ready tic-mwhy
blocked tic-yxrw tic-5lpp
```

(The state of this repository before `tic-zmz1` was closed. No `last-child` line: its parent `tic-sa3b` had other open children.)

- `status` is always present and always the first line; it is the target's real status.
- Kinds appear in the fixed order above; lines of one kind are sorted by ID (`LC_ALL=C`), and the deps of a `blocked` line are sorted the same way, so output is deterministic.
- A kind with no facts prints no line. A target with no impact prints only `status`.
- Contract for consumers: match on the first word and ignore unknown kinds, so new kinds can be added without breaking them. Existing kinds and their field order do not change within 1.x.

Intended use:

```bash
out=$("$TK_SCRIPT" impact --porcelain "$id") || exit $?
grep -qE '^blocker |^child ' <<<"$out" && refuse
awk '$1 == "ready" { print $2 }' <<<"$out"      # unblock report
```

### Human

```
tic-zmz1 [open] Decide guard style: shadow built-ins, new verbs, or core changes

Becomes ready:
- tic-6rw0 [open] Add guarded start and reopen plugins
- tic-mwhy [open] Add guarded dep and undep plugins

Still blocked by others:
- tic-yxrw [open] Add guarded close plugin <- tic-5lpp
```

The last-child line, when the fact holds:

```
Last open child of tic-sa3b [open] Add guard and lifecycle plugins - consider closing the parent
```

- Header line: `<id> [<status>] <title>`.
- Sections in the order `Open blockers:`, `Open children:`, `Becomes ready:`, `Still blocked by others:`, then the last-child line. Each section is preceded by an empty line and printed only when it has entries.
- Entry format is the one `cmd_show` uses: `- <id> [<status>] <title>`. A dangling blocker prints `- <id> [missing]`. `Still blocked by others:` entries end with ` <- <dep>[, <dep>...]`.
- When the target's status is `closed`, the heading `Becomes ready:` is replaced by `Already closed. Reopening would re-block:`; everything else is unchanged.
- When there is no blocker, child, dependent or last-child fact, the header is followed by an empty line and `No impact: nothing depends on <id>`.
- Same ordering rules as porcelain. Nothing is written to stderr on success.

## Files

| File | Change |
|---|---|
| `plugins/ticket-impact` | New, executable. Header `# tk-plugin: Show what closing a ticket would change`, `# tk-plugin-version: 1.0.0`. Skeleton (flag loop, `TICKETS_DIR` check, `set -euo pipefail`) follows `plugins/ticket-lint`. |
| `features/ticket_impact.feature` | New. Uses existing steps only (ticket exists, with parent, depends on, has status, exit code, output contains / matches / line N). Add a step only if a scenario cannot be expressed otherwise. |
| `plugins/README.md` | New section: usage, human example, porcelain format and the consumer contract. |
| `README.md` | Mention `ticket-impact` (`tk impact`) next to `ticket-lint` in the Plugins section. |
| `CHANGELOG.md` | `### Plugins`: `ticket-impact 1.0.0: New plugin, ...`. |

Not added to `pkg/extras.txt` (new plugin, not a core extraction).

## Testing

Behave scenarios, written before the code they cover (red, then green):

1. Dependent with a single blocker is listed under `Becomes ready:`.
2. Dependent with a second open blocker is listed under `Still blocked by others:` with `<- <id>`.
3. Open children are listed; closed children are not.
4. Last open child of an open parent is reported; not reported when a sibling is open, when the parent is closed, or when there is no parent.
5. Closed dependents are ignored.
6. Partial ID works; ambiguous partial ID exits 1; unknown ID exits 1.
7. Open blockers of the target are listed, including a dangling ID as `[missing]`.
8. `--porcelain`: exact lines and order for a ticket that has every fact kind; `status` first; a `blocked` line with two deps joined by a comma.
9. Closed target: human heading `Already closed. Reopening would re-block:`, porcelain `status closed` with the same `ready` lines.
10. No impact: human `No impact:` line, porcelain prints only `status`.
11. No argument, two IDs, unknown flag: exit 2 with usage on stderr; `--help` exits 0.
12. `tk help` lists `impact` with its description.

`make test` must pass with the whole suite.

## Ticket bookkeeping

- `tic-5lpp`: note that `--porcelain` replaces `--ids-ready`, with the reason. The body is not rewritten.
- `tic-yxrw`: note that its design line "reuse `tk impact --ids-ready`" now reads `tk impact --porcelain` (`blocker` / `child` lines for the guard, `ready` lines for the unblock report, `last-child` for the parent hint).
- `tic-6rw0`: note that the re-blocked dependents are the `ready` lines of `tk impact --porcelain <id>` taken while the ticket is still closed.
