# ticket-close Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `plugins/ticket-close` 1.0.0, a plugin that shadows `tk close`: it refuses unsafe closes, writes the `Closed: <resolution>` note and reports what became ready.

**Architecture:** One standalone bash file with no graph logic of its own. IDs are resolved by asking core (`tk super show`), every graph fact comes from one `tk impact --porcelain` call taken before the close, and every write goes through `tk super add-note` / `tk super close`. The core `ticket` script is not touched.

**Tech Stack:** bash, POSIX awk (the system awk here is mawk; the code also runs under busybox awk), the `ticket-impact` plugin. Tests: Behave (`make test`, needs `uv`).

**Spec:** `docs/superpowers/specs/2026-09-17-ticket-close-guard-design.md` - read it first; this plan implements it section by section.

## Global Constraints

- Ticket: `tic-yxrw` (already `in_progress`). Worktree: `.claude/worktrees/tic-yxrw-guarded-close`, branch `worktree-tic-yxrw-guarded-close` (already checked out). Do not switch branches, do not `cd` to the main checkout.
- No changes to the core `ticket` script. The plugin never edits a ticket file itself: writes only through `"$TK_SCRIPT" super add-note` and `"$TK_SCRIPT" super close`.
- No changes to `plugins/ticket-impact` (stays 1.0.0, no `target` porcelain line).
- No new step definitions in `features/steps/ticket_steps.py` (the `tic-mwhy` branch adds one to the same file; a new one here would conflict). Absence of a note is asserted with `ticket show` + `the output should not contain`.
- POSIX awk only: no `asort`, no `gensub`, no `length(array)`. bash 3.2 compatible: no `mapfile`, no associative arrays, no `${var,,}`, never expand a possibly empty array as `"${arr[@]}"` under `set -u`.
- Plugin metadata in the first 10 lines, exactly: `# tk-plugin: Guarded close: refuse unsafe closes, record the reason, report what got unblocked` and `# tk-plugin-version: 1.0.0`.
- Exit codes: 0 closed or already closed; 1 guard refused / ID or `--ref` not found or ambiguous / `--ref` is the target / `ticket-impact` missing / a delegated built-in failed; 2 usage error or no tickets directory.
- Note prefixes are fixed: `Closed: done - `, `Closed: won't do - `, `Closed: duplicate of <id>`, `Closed: superseded by <id>`; the forced line is `Forced: open blockers <ids>; open children <ids>; open dependents <ids>` (only the parts that apply, in that order, IDs joined with `, `).
- NOT added to `pkg/extras.txt` (new plugin, not a core extraction).
- Commit messages: conventional prefix, ticket in parentheses, and NO attribution trailers of any kind (no `Co-Authored-By`, no "Generated with"). The message ends with its last line of real content.
- Before every `git commit` load the `managing-tk-tickets` skill. No commit in this plan closes `tic-yxrw`; closing needs the user's explicit yes (Task 5).
- Run one feature with `uv run --with behave behave features/ticket_close_guard.feature`; the whole suite with `make test`.
- The code blocks below were run against this repository at commit `f509fa2`: the red/green counts in the "Expected" lines are real. If a count differs, stop and find out why before going on.

---

### Task 1: CLI, ID resolution, note and close

Covers the spec sections CLI, ID resolution, Steps 1-5 and 7, Note text (without `Forced:`), and the testing rows Notes, Usage, IDs, Already closed, Bypass.

**Files:**
- Create: `plugins/ticket-close` (mode 755)
- Create: `features/ticket_close_guard.feature`
- Modify: `features/ticket_status.feature:36` (core scenario goes through `super`)

**Interfaces:**
- Consumes: `"$TK_SCRIPT" super show <id>` (front matter line `id: <full-id>`; core's error text and exit 1 for unknown / ambiguous IDs), `"$TK_SCRIPT" impact --porcelain <id>` (first line `status <status>`), `"$TK_SCRIPT" super add-note <id> <text>`, `"$TK_SCRIPT" super close <id>` (prints `Updated <id> -> closed`).
- Produces: shell variables later tasks rely on - `id` (full target ID), `reason`, `text`, `have_text`, `ref` (full ID), `force` (0/1), `facts` (the porcelain text), `note` (the note text); functions `usage`, `die_usage <msg>`, `resolve_id <id>`.

- [ ] **Step 1: Point the core close scenario at the built-in**

`features/environment.py` puts `plugins/` on `PATH` for the whole suite, so once `plugins/ticket-close` exists, `ticket close test-0001` reaches the guard. The scenario tests core behaviour, so it goes through `super`. In `features/ticket_status.feature` replace

```gherkin
  Scenario: Close command sets status to closed
    When I run "ticket close test-0001"
```

with

```gherkin
  Scenario: Close command sets status to closed
    When I run "ticket super close test-0001"
```

The three `Then` / `And` lines of the scenario stay as they are.

- [ ] **Step 2: Write the failing scenarios**

Create `features/ticket_close_guard.feature` with exactly this content:

```gherkin
Feature: Guarded Close
  As a user or an agent
  I want tk close to refuse unsafe closes and record why a ticket was closed
  So that dependents never become ready by mistake

  Background:
    Given a clean tickets directory

  # --- Note text ---

  Scenario: Done note
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done -m \"guard plugin shipped\""
    Then the exit code should be 0
    And the output line 1 should contain "Updated cl-0001 -> closed"
    And the output line 2 should contain "Note: Closed: done - guard plugin shipped"
    And ticket "cl-0001" should contain "Closed: done - guard plugin shipped"
    And ticket "cl-0001" should contain a timestamp in notes

  Scenario: Won't-do note
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason wontdo -m \"out of scope\""
    Then the exit code should be 0
    And ticket "cl-0001" should contain "Closed: won't do - out of scope"

  Scenario: Duplicate note
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Original"
    When I run "ticket close cl-0001 --reason duplicate --ref cl-0002"
    Then the exit code should be 0
    And the output line 2 should contain "Note: Closed: duplicate of cl-0002"
    And ticket "cl-0001" should contain "Closed: duplicate of cl-0002"

  Scenario: Superseded note with a text
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Replacement"
    When I run "ticket close cl-0001 --reason superseded --ref cl-0002 -m \"merged scope\""
    Then the exit code should be 0
    And ticket "cl-0001" should contain "Closed: superseded by cl-0002 - merged scope"

  Scenario: Duplicate note with a text
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Original"
    When I run "ticket close cl-0001 --reason duplicate --ref cl-0002 -m \"same bug\""
    Then the exit code should be 0
    And ticket "cl-0001" should contain "Closed: duplicate of cl-0002 - same bug"

  Scenario: Partial --ref is written as the full ID
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Original"
    When I run "ticket close cl-0001 --reason=duplicate --ref=0002"
    Then the exit code should be 0
    And ticket "cl-0001" should contain "Closed: duplicate of cl-0002"

  Scenario: A closed ticket may be the --ref
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Original"
    And ticket "cl-0002" has status "closed"
    When I run "ticket close cl-0001 --reason duplicate --ref cl-0002"
    Then the exit code should be 0

  # --- Usage errors ---

  Scenario: Missing --reason is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001"
    Then the exit code should be 2
    And the error output should contain "Error: --reason is required"
    And the error output should contain "Usage: tk close <id> --reason done|wontdo|duplicate|superseded"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Invalid reason is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason fixed -m \"x\""
    Then the exit code should be 2
    And the error output should contain "invalid --reason 'fixed'"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Done without -m is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done"
    Then the exit code should be 2
    And the error output should contain "--reason done requires -m <text>"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Won't-do without -m is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason wontdo"
    Then the exit code should be 2
    And the error output should contain "--reason wontdo requires -m <text>"

  Scenario: Empty -m is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done -m \" \""
    Then the exit code should be 2
    And the error output should contain "-m must not be empty"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Duplicate without --ref is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason duplicate"
    Then the exit code should be 2
    And the error output should contain "--reason duplicate requires --ref <id>"

  Scenario: --ref with done is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Other"
    When I run "ticket close cl-0001 --reason done -m \"x\" --ref cl-0002"
    Then the exit code should be 2
    And the error output should contain "--ref is only valid with --reason duplicate|superseded"

  Scenario: Unknown flag is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done -m \"x\" --yes"
    Then the exit code should be 2
    And the error output should contain "unknown option: --yes"

  Scenario: No ID is a usage error
    When I run "ticket close --reason done -m \"x\""
    Then the exit code should be 2
    And the error output should contain "expected exactly one <id>"

  Scenario: Two IDs are a usage error
    Given a ticket exists with ID "cl-0001" and title "First"
    And a ticket exists with ID "cl-0002" and title "Second"
    When I run "ticket close cl-0001 cl-0002 --reason done -m \"x\""
    Then the exit code should be 2
    And ticket "cl-0001" should have field "status" with value "open"
    And ticket "cl-0002" should have field "status" with value "open"

  Scenario: Flags may come before the ID
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close --reason=done -m \"shipped\" cl-0001"
    Then the exit code should be 0
    And ticket "cl-0001" should have field "status" with value "closed"

  Scenario: Help prints usage and exits 0
    When I run "ticket close --help"
    Then the exit code should be 0
    And the output should contain "Usage: tk close <id> --reason"
    And the output should contain "Bypass the guard: tk super close <id>"

  # --- ID resolution ---

  Scenario: Partial target ID works
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close 0001 --reason done -m \"shipped\""
    Then the exit code should be 0
    And the output line 1 should contain "Updated cl-0001 -> closed"

  Scenario: Unknown ID fails with core's message
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close nope --reason done -m \"x\""
    Then the exit code should be 1
    And the error output should contain "ticket 'nope' not found"

  Scenario: Ambiguous ID fails
    Given a ticket exists with ID "cl-0001" and title "First"
    And a ticket exists with ID "cl-0002" and title "Second"
    When I run "ticket close cl- --reason done -m \"x\""
    Then the exit code should be 1
    And the error output should contain "ambiguous ID 'cl-' matches multiple tickets"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Unknown --ref fails and leaves the target open
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason duplicate --ref nope"
    Then the exit code should be 1
    And the error output should contain "ticket 'nope' not found"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: A ticket cannot be a duplicate of itself
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason duplicate --ref 0001"
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 cannot be a duplicate of itself"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: A ticket cannot be superseded by itself
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason superseded --ref cl-0001"
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 cannot be superseded by itself"

  # --- Already closed ---

  Scenario: Closing a closed ticket changes nothing
    Given a ticket exists with ID "cl-0001" and title "Target"
    And ticket "cl-0001" has status "closed"
    When I run "ticket close cl-0001 --reason done -m \"again\""
    Then the exit code should be 0
    And the output should be "cl-0001 is already closed"
    When I run "ticket show cl-0001"
    Then the output should not contain "Closed:"

  # --- Bypass ---

  Scenario: tk super close bypasses the guard
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker"
    And ticket "cl-0001" depends on "cl-0002"
    When I run "ticket super close cl-0001"
    Then the exit code should be 0
    And the output should be "Updated cl-0001 -> closed"
    And ticket "cl-0001" should have field "status" with value "closed"
    When I run "ticket show cl-0001"
    Then the output should not contain "Closed:"
```

- [ ] **Step 3: Run the feature to verify it fails**

Run: `uv run --with behave behave features/ticket_close_guard.feature 2>&1 | tail -4`
Expected: `5 scenarios passed, 22 failed`. Without the plugin the built-in `close` ignores the extra arguments, closes the ticket with exit 0 and writes no note, so every scenario that expects a note, exit 1 or exit 2 fails. The 5 that pass expect only a plain close.

- [ ] **Step 4: Write the plugin**

Create `plugins/ticket-close` with exactly this content:

```bash
#!/usr/bin/env bash
# tk-plugin: Guarded close: refuse unsafe closes, record the reason, report what got unblocked
# tk-plugin-version: 1.0.0
set -euo pipefail

usage() {
    echo "Usage: tk close <id> --reason done|wontdo|duplicate|superseded [-m <text>] [--ref <id>] [--force]"
    echo "  --reason <r>  resolution; done and wontdo require -m, duplicate and superseded require --ref"
    echo "  -m <text>     what was delivered / why it will not be done; written into the Closed: note"
    echo "  --ref <id>    the ticket this one duplicates or is superseded by"
    echo "  --force       close despite open blockers, children or dependents; recorded in the note"
    echo "Bypass the guard: tk super close <id>"
}

die_usage() {
    echo "Error: $1" >&2
    usage >&2
    exit 2
}

if [[ -z "${TK_SCRIPT:-}" ]]; then
    echo "Error: TK_SCRIPT is not set; run this plugin through tk" >&2
    exit 2
fi

reason="" text="" ref="" have_text=0 have_ref=0 force=0
ids=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --reason)
            [[ $# -ge 2 ]] || die_usage "--reason requires a value"
            reason="$2"; shift 2 ;;
        --reason=*) reason="${1#--reason=}"; shift ;;
        -m)
            [[ $# -ge 2 ]] || die_usage "-m requires a text"
            text="$2"; have_text=1; shift 2 ;;
        --ref)
            [[ $# -ge 2 ]] || die_usage "--ref requires a ticket ID"
            ref="$2"; have_ref=1; shift 2 ;;
        --ref=*) ref="${1#--ref=}"; have_ref=1; shift ;;
        --force) force=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; while [[ $# -gt 0 ]]; do ids+=("$1"); shift; done ;;
        -*) die_usage "unknown option: $1" ;;
        *) ids+=("$1"); shift ;;
    esac
done

[[ ${#ids[@]} -eq 1 ]] || die_usage "expected exactly one <id>"
[[ -n "$reason" ]] || die_usage "--reason is required"
case "$reason" in
    done|wontdo)
        [[ $have_ref -eq 0 ]] || die_usage "--ref is only valid with --reason duplicate|superseded"
        [[ $have_text -eq 1 ]] || die_usage "--reason $reason requires -m <text>"
        [[ -n "${text//[[:space:]]/}" ]] || die_usage "-m must not be empty"
        ;;
    duplicate|superseded)
        [[ $have_ref -eq 1 && -n "${ref//[[:space:]]/}" ]] || die_usage "--reason $reason requires --ref <id>"
        [[ $have_text -eq 0 || -n "${text//[[:space:]]/}" ]] || die_usage "-m must not be empty"
        ;;
    *) die_usage "invalid --reason '$reason' (done|wontdo|duplicate|superseded)" ;;
esac

if [[ -z "${TICKETS_DIR:-}" || ! -d "$TICKETS_DIR" ]]; then
    echo "Error: no .tickets directory found (searched parent directories)" >&2
    exit 2
fi

# Full ID on stdout. Core resolves it (exact or partial) and prints its own
# errors; the output is captured first so pipefail never sees a SIGPIPE.
resolve_id() {
    local out
    out=$("$TK_SCRIPT" super show "$1") || return 1
    awk '/^id:/ && !done { print $2; done = 1 }' <<< "$out"
}

id=$(resolve_id "${ids[0]}") || exit 1
if [[ $have_ref -eq 1 ]]; then
    ref=$(resolve_id "$ref") || exit 1
    if [[ "$ref" == "$id" ]]; then
        if [[ "$reason" == "duplicate" ]]; then
            echo "Error: $id cannot be a duplicate of itself" >&2
        else
            echo "Error: $id cannot be superseded by itself" >&2
        fi
        exit 1
    fi
fi

if ! command -v ticket-impact >/dev/null 2>&1 && ! command -v tk-impact >/dev/null 2>&1; then
    echo "Error: tk close needs the ticket-impact plugin on PATH" >&2
    echo "Use 'tk super close' to bypass the guard" >&2
    exit 1
fi

# Taken before the close: tk impact computes every fact as if the ticket were
# already closed, so this is the guard input and the forecast for the report.
facts=$("$TK_SCRIPT" impact --porcelain "$id") || exit $?

if [[ "$(awk '$1 == "status" { print $2 }' <<< "$facts")" == "closed" ]]; then
    echo "$id is already closed"
    exit 0
fi

case "$reason" in
    done) note="Closed: done - $text" ;;
    wontdo) note="Closed: won't do - $text" ;;
    duplicate) note="Closed: duplicate of $ref" ;;
    superseded) note="Closed: superseded by $ref" ;;
esac
if [[ "$reason" != "done" && "$reason" != "wontdo" && $have_text -eq 1 ]]; then
    note="$note - $text"
fi

"$TK_SCRIPT" super add-note "$id" "$note" >/dev/null || exit 1
if ! "$TK_SCRIPT" super close "$id"; then
    echo "Error: note written but tk super close failed" >&2
    exit 1
fi
echo "Note: $note"
```

Then: `chmod +x plugins/ticket-close`

Notes for the implementer:
- `resolve_id` captures the whole `tk super show` output before parsing, and the awk program never calls `exit`. Both are deliberate: with `set -o pipefail`, `show | awk '... exit'` makes `show` die of SIGPIPE and the pipeline fail with 141.
- Arguments are validated before anything is resolved, so a usage error never depends on the state of `.tickets/`.
- `tk impact` computes every fact as if the target were closed, which is why it is called before the close.

- [ ] **Step 5: Run the feature to verify it passes**

Run: `uv run --with behave behave features/ticket_close_guard.feature 2>&1 | tail -4`
Expected: `27 scenarios passed, 0 failed`.

- [ ] **Step 6: Run the whole suite**

Run: `make test 2>&1 | tail -4`
Expected: `0 failed` for features, scenarios and steps (237 scenarios). If `features/ticket_status.feature` "Close command sets status to closed" fails with exit 2, Step 1 was skipped.

- [ ] **Step 7: Commit**

```bash
git add plugins/ticket-close features/ticket_close_guard.feature features/ticket_status.feature
git commit -m "feat: ticket-close plugin - reason, note and ID resolution (tic-yxrw)"
```

---

### Task 2: Guards and --force

Covers spec Steps 6 and the `Forced:` line of Note text, and the testing rows Guards, Dependents, Force.

**Files:**
- Modify: `plugins/ticket-close` (everything below the already-closed block)
- Modify: `features/ticket_close_guard.feature` (append)

**Interfaces:**
- Consumes: from Task 1 - `id`, `reason`, `text`, `have_text`, `ref`, `force`, `facts`. Porcelain kinds `blocker <id>`, `child <id>`, `ready <id>`, `blocked <id> <deps>`.
- Produces: function `facts_of <kind>...` - the second field of every porcelain line whose first word is one of the given kinds, joined with `, `, empty string when there is none (Task 3 calls `facts_of ready` and `facts_of last-child`); variables `blockers`, `children`, `dependents`, `first_line` (first line of the note, used for the `Note:` output line).

- [ ] **Step 1: Write the failing scenarios**

Append to `features/ticket_close_guard.feature`, after one blank line:

```gherkin
  # --- Guards: open blockers and open children ---

  Scenario: Open blocker refuses the close
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker"
    And ticket "cl-0001" depends on "cl-0002"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 has open blockers: cl-0002"
    And the error output should contain "Use --force to close anyway, or 'tk super close' to bypass the guard"
    And the output should be empty
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: A refused close writes no note
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker"
    And ticket "cl-0001" depends on "cl-0002"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    And I run "ticket show cl-0001"
    Then the output should not contain "Closed:"

  Scenario: Open child refuses the close
    Given a ticket exists with ID "cl-0001" and title "Parent"
    And a ticket exists with ID "cl-0002" and title "Child" with parent "cl-0001"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 has open children: cl-0002"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Every violation is reported at once
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker one"
    And a ticket exists with ID "cl-0003" and title "Blocker two"
    And a ticket exists with ID "cl-0004" and title "Child" with parent "cl-0001"
    And ticket "cl-0001" depends on "cl-0002"
    And ticket "cl-0001" depends on "cl-0003"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 has open blockers: cl-0002, cl-0003"
    And the error output should contain "Error: cl-0001 has open children: cl-0004"

  Scenario: Closed blocker and closed child do not refuse
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker"
    And a ticket exists with ID "cl-0003" and title "Child" with parent "cl-0001"
    And ticket "cl-0001" depends on "cl-0002"
    And ticket "cl-0002" has status "closed"
    And ticket "cl-0003" has status "closed"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 0
    And ticket "cl-0001" should have field "status" with value "closed"
    And the error output should be empty

  # --- Guards: open dependents of a close that delivers nothing ---

  Scenario: Won't-do close with an open dependent is refused
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason wontdo -m \"out of scope\""
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 has open dependents that would see it as resolved: cl-0002"
    And the error output should contain "tk undep"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Duplicate close with an open dependent is refused
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And a ticket exists with ID "cl-0003" and title "Original"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason duplicate --ref cl-0003"
    Then the exit code should be 1
    And the error output should contain "open dependents that would see it as resolved: cl-0002"

  Scenario: Superseded close with an open dependent is refused
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And a ticket exists with ID "cl-0003" and title "Replacement"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason superseded --ref cl-0003"
    Then the exit code should be 1
    And the error output should contain "open dependents that would see it as resolved: cl-0002"

  Scenario: A dependent that is also blocked by another ticket still counts
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And a ticket exists with ID "cl-0003" and title "Other blocker"
    And ticket "cl-0002" depends on "cl-0001"
    And ticket "cl-0002" depends on "cl-0003"
    When I run "ticket close cl-0001 --reason wontdo -m \"out of scope\""
    Then the exit code should be 1
    And the error output should contain "open dependents that would see it as resolved: cl-0002"

  Scenario: Done close with open dependents is allowed
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 0
    And ticket "cl-0001" should have field "status" with value "closed"

  Scenario: Closed dependents do not refuse a won't-do close
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And ticket "cl-0002" depends on "cl-0001"
    And ticket "cl-0002" has status "closed"
    When I run "ticket close cl-0001 --reason wontdo -m \"out of scope\""
    Then the exit code should be 0
    And ticket "cl-0001" should have field "status" with value "closed"

  # --- --force ---

  Scenario: Force closes despite blocker and child and records it
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker"
    And a ticket exists with ID "cl-0003" and title "Child" with parent "cl-0001"
    And ticket "cl-0001" depends on "cl-0002"
    When I run "ticket close cl-0001 --reason done -m \"shipped\" --force"
    Then the exit code should be 0
    And the error output should contain "Warning: closing cl-0001 with open blockers: cl-0002"
    And the error output should contain "Warning: closing cl-0001 with open children: cl-0003"
    And ticket "cl-0001" should have field "status" with value "closed"
    And ticket "cl-0001" should contain "Closed: done - shipped"
    And ticket "cl-0001" should contain "Forced: open blockers cl-0002; open children cl-0003"

  Scenario: Force on a won't-do close records the dependents
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason wontdo -m \"out of scope\" --force"
    Then the exit code should be 0
    And the error output should contain "Warning: closing cl-0001 with open dependents: cl-0002"
    And ticket "cl-0001" should contain "Forced: open dependents cl-0002"

  Scenario: Force without violations writes no Forced line
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done -m \"shipped\" --force"
    And I run "ticket show cl-0001"
    Then the output should contain "Closed: done - shipped"
    And the output should not contain "Forced:"
```

- [ ] **Step 2: Run the feature to verify it fails**

Run: `uv run --with behave behave features/ticket_close_guard.feature 2>&1 | tail -4`
Expected: `31 scenarios passed, 10 failed`. The failures are the scenarios that expect exit 1, a `Warning:` line or a `Forced:` line; the 4 new ones that already pass expect a plain successful close.

- [ ] **Step 3: Add the guards**

In `plugins/ticket-close`, keep everything up to and including

```bash
if [[ "$(awk '$1 == "status" { print $2 }' <<< "$facts")" == "closed" ]]; then
    echo "$id is already closed"
    exit 0
fi
```

and replace everything below that block (the note `case`, the `add-note` / `close` calls and the final `echo`) with:

```bash
# IDs (second field) of the porcelain lines of the given kinds, joined with ", "
facts_of() {
    awk -v kinds=" $* " '
        index(kinds, " " $1 " ") { out = out (out == "" ? "" : ", ") $2 }
        END { print out }
    ' <<< "$facts"
}

blockers=$(facts_of blocker)
children=$(facts_of child)
dependents=""
[[ "$reason" == "done" ]] || dependents=$(facts_of ready blocked)

if [[ -n "$blockers$children$dependents" ]]; then
    if [[ $force -eq 0 ]]; then
        [[ -z "$blockers" ]] || echo "Error: $id has open blockers: $blockers" >&2
        [[ -z "$children" ]] || echo "Error: $id has open children: $children" >&2
        [[ -z "$dependents" ]] || echo "Error: $id has open dependents that would see it as resolved: $dependents (settle them first: tk undep / tk dep)" >&2
        echo "Use --force to close anyway, or 'tk super close' to bypass the guard" >&2
        exit 1
    fi
    [[ -z "$blockers" ]] || echo "Warning: closing $id with open blockers: $blockers" >&2
    [[ -z "$children" ]] || echo "Warning: closing $id with open children: $children" >&2
    [[ -z "$dependents" ]] || echo "Warning: closing $id with open dependents: $dependents" >&2
fi

case "$reason" in
    done) note="Closed: done - $text" ;;
    wontdo) note="Closed: won't do - $text" ;;
    duplicate) note="Closed: duplicate of $ref" ;;
    superseded) note="Closed: superseded by $ref" ;;
esac
if [[ "$reason" != "done" && "$reason" != "wontdo" && $have_text -eq 1 ]]; then
    note="$note - $text"
fi
first_line="$note"

forced=""
[[ -z "$blockers" ]] || forced="open blockers $blockers"
[[ -z "$children" ]] || forced="${forced:+$forced; }open children $children"
[[ -z "$dependents" ]] || forced="${forced:+$forced; }open dependents $dependents"
[[ -z "$forced" ]] || note="$note"$'\n'"Forced: $forced"

"$TK_SCRIPT" super add-note "$id" "$note" >/dev/null || exit 1
if ! "$TK_SCRIPT" super close "$id"; then
    echo "Error: note written but tk super close failed" >&2
    exit 1
fi
echo "Note: $first_line"
```

Notes for the implementer:
- `facts_of ready blocked` is the list of open dependents: a dependent still blocked by another ticket carries the same falsely resolved edge, so both kinds count. For a `blocked <id> <deps>` line the second field is the dependent's ID.
- The dependents guard applies to `wontdo`, `duplicate` and `superseded` only. For `done` the dependents are supposed to become ready.
- All violations are printed before exiting, one `Error:` line per kind.
- The `Forced:` line goes into the same note as a second line, so `grep '^Closed: '` and `ticket-lint`'s `close-note` rule keep matching the first line. It is written only when a guard was actually overridden.

- [ ] **Step 4: Run the feature to verify it passes**

Run: `uv run --with behave behave features/ticket_close_guard.feature 2>&1 | tail -4`
Expected: `41 scenarios passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/ticket-close features/ticket_close_guard.feature
git commit -m "feat: ticket-close guards for blockers, children and dependents, --force (tic-yxrw)"
```

---

### Task 3: Unblock report and portability checks

Covers spec Step 8, the testing row Report, the busybox awk run and the hand check of the "`ticket-impact` missing" branch.

**Files:**
- Modify: `plugins/ticket-close` (append)
- Modify: `features/ticket_close_guard.feature` (append)

**Interfaces:**
- Consumes: from Task 2 - `facts_of <kind>...`. Porcelain kinds `ready <id>` (sorted by ID) and `last-child <parent-id>` (at most one line).
- Produces: the final stdout contract - line 1 `Updated <id> -> closed`, line 2 `Note: <first note line>`, line 3 `Now ready: <ids>` or `Nothing became ready`, optional line 4 `Last open child of <parent> closed - consider closing <parent>`.

- [ ] **Step 1: Write the failing scenarios**

Append to `features/ticket_close_guard.feature`, after one blank line:

```gherkin
  # --- Report ---

  Scenario: Unblocked dependents are reported, still blocked ones are not
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Becomes ready"
    And a ticket exists with ID "cl-0003" and title "Still blocked"
    And a ticket exists with ID "cl-0004" and title "Other blocker"
    And ticket "cl-0002" depends on "cl-0001"
    And ticket "cl-0003" depends on "cl-0001"
    And ticket "cl-0003" depends on "cl-0004"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 0
    And the output line 3 should contain "Now ready: cl-0002"
    And the output should not contain "cl-0003"

  Scenario: Several unblocked dependents are listed in ID order
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0003" and title "Second"
    And a ticket exists with ID "cl-0002" and title "First"
    And ticket "cl-0003" depends on "cl-0001"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the output line 3 should contain "Now ready: cl-0002, cl-0003"

  Scenario: Nothing became ready
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the output line 3 should contain "Nothing became ready"
    And the output line count should be 3

  Scenario: Parent hint when the last open child closes
    Given a ticket exists with ID "cl-0001" and title "Parent"
    And a ticket exists with ID "cl-0002" and title "Child" with parent "cl-0001"
    When I run "ticket close cl-0002 --reason done -m \"shipped\""
    Then the exit code should be 0
    And the output line 4 should contain "Last open child of cl-0001 closed - consider closing cl-0001"

  Scenario: No parent hint while a sibling is open
    Given a ticket exists with ID "cl-0001" and title "Parent"
    And a ticket exists with ID "cl-0002" and title "Child" with parent "cl-0001"
    And a ticket exists with ID "cl-0003" and title "Sibling" with parent "cl-0001"
    When I run "ticket close cl-0002 --reason done -m \"shipped\""
    Then the exit code should be 0
    And the output should not contain "Last open child"
```

- [ ] **Step 2: Run the feature to verify it fails**

Run: `uv run --with behave behave features/ticket_close_guard.feature 2>&1 | tail -4`
Expected: `42 scenarios passed, 4 failed` ("No parent hint while a sibling is open" already passes).

- [ ] **Step 3: Add the report**

Append to the end of `plugins/ticket-close`, after one blank line:

```bash
ready=$(facts_of ready)
if [[ -n "$ready" ]]; then
    echo "Now ready: $ready"
else
    echo "Nothing became ready"
fi
parent=$(facts_of last-child)
[[ -z "$parent" ]] || echo "Last open child of $parent closed - consider closing $parent"
```

The complete file must now be identical to the listing in the appendix at the end of this plan.

- [ ] **Step 4: Run the feature, then the whole suite**

Run: `uv run --with behave behave features/ticket_close_guard.feature 2>&1 | tail -4`
Expected: `46 scenarios passed, 0 failed`.

Run: `make test 2>&1 | tail -4`
Expected: `16 features passed, 0 failed`, `256 scenarios passed, 0 failed`.

- [ ] **Step 5: Run the feature with busybox awk first in PATH**

Use the session scratchpad directory (not `/tmp` directly) for `BB`:

```bash
BB=<scratchpad>/bbawk
mkdir -p "$BB"
ln -sf /usr/bin/busybox "$BB/awk"
PATH="$BB:$PATH" uv run --with behave behave features/ticket_close_guard.feature features/ticket_impact.feature 2>&1 | tail -4
```

Expected: `2 features passed, 0 failed`.

- [ ] **Step 6: Check the "ticket-impact missing" branch by hand**

The suite always has `plugins/` on `PATH`, so this branch has no scenario. `ONLY` holds a copy of `ticket-close` alone; `TKDIR` is a throwaway project. Both live in the scratchpad.

```bash
ONLY=<scratchpad>/only; TKDIR=<scratchpad>/tkdir; REPO=$PWD
mkdir -p "$ONLY" "$TKDIR/.tickets"
cp plugins/ticket-close "$ONLY/"
cd "$TKDIR"
"$REPO/ticket" create "Target" >/dev/null
PATH="$ONLY:/usr/bin:/bin" "$REPO/ticket" close tkd --reason done -m x; echo "exit=$?"
grep '^status' .tickets/*.md
cd "$REPO"
```

Expected output, exactly:

```
Error: tk close needs the ticket-impact plugin on PATH
Use 'tk super close' to bypass the guard
exit=1
status: open
```

- [ ] **Step 7: Commit**

```bash
git add plugins/ticket-close features/ticket_close_guard.feature
git commit -m "feat: ticket-close reports unblocked tickets and the parent hint (tic-yxrw)"
```

---

### Task 4: Documentation, packaging, skill

Covers the spec section Documentation and packaging.

**Files:**
- Modify: `README.md` (usage block, official-plugins paragraph)
- Modify: `plugins/README.md` (new `## ticket-close` section at the end)
- Modify: `CHANGELOG.md` (`## [Unreleased]` -> `### Plugins`)
- Modify: `scripts/publish-aur.sh` (the `extra_deps` case in the plugin PKGBUILD generator)
- Modify: `scripts/publish-homebrew.sh` (`generate_plugin_formula`)
- Modify: `skills/managing-tk-tickets/SKILL.md` (four minimal edits)

**Interfaces:**
- Consumes: the CLI and output contract of Tasks 1-3.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: README.md usage block**

In the usage code block, under `Official plugins (installed separately):`, after the line

```
  lint [--conventions] [--strict]    Check tickets for broken graph invariants
```

add (the `impact` line was missing from this block; `close` depends on it, so it is added here too):

```
  impact [--porcelain] <id>          Show what closing a ticket would change
  close <id> --reason done|wontdo|duplicate|superseded [-m text] [--ref id] [--force]
                           Guarded close, shadows the built-in (needs impact): refuses open
                           blockers/children, writes the Closed: note, lists what became ready
```

The core line `close <id>                 Set status to closed` stays: it documents the built-in (`tk super close`).

- [ ] **Step 2: README.md official-plugins paragraph**

In the paragraph that starts with `**Official plugins** live in`, replace the tail

```
and has a `--porcelain` mode for scripts. None of them is part of `ticket-extras`: copy or symlink `plugins/ticket-lint`, `plugins/ticket-find` and `plugins/ticket-impact` into your PATH (or put the `plugins/` directory on your PATH), or install the `ticket-lint`, `ticket-find` and `ticket-impact` packages.
```

with

```
and has a `--porcelain` mode for scripts. `ticket-close` shadows `tk close` with a guard: `tk close <id> --reason done|wontdo|duplicate|superseded` refuses a ticket with open blockers or open children (and, for the reasons that deliver nothing, one that open tickets still depend on), writes the `Closed: <resolution>` note and prints which tickets became ready; it needs `ticket-impact`, `--force` overrides the guard and `tk super close` bypasses it. None of them is part of `ticket-extras`: copy or symlink `plugins/ticket-lint`, `plugins/ticket-find`, `plugins/ticket-impact` and `plugins/ticket-close` into your PATH (or put the `plugins/` directory on your PATH), or install the `ticket-lint`, `ticket-find`, `ticket-impact` and `ticket-close` packages.
```

- [ ] **Step 3: plugins/README.md**

Append this section at the end of the file, after one blank line:

````markdown
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

Exit codes: 0 closed or already closed; 1 guard refused, ticket or `--ref` not found / ambiguous, `--ref` is the ticket itself, `ticket-impact` missing; 2 usage error or no tickets directory.

Requires bash, POSIX awk and the `ticket-impact` plugin on `PATH` (the packages declare the dependency). It contains no graph logic: every fact comes from `tk impact --porcelain`, IDs are resolved by `tk super show`. Bypass: `tk super close <id>` runs the built-in. `tk status <id> closed` is not guarded; `tk lint --conventions` reports such a close as `close-note`.
````

- [ ] **Step 4: CHANGELOG.md**

Under `## [Unreleased]` -> `### Plugins`, after the `ticket-impact 1.0.0` line, add:

```markdown
- ticket-close 1.0.0: New plugin that shadows the built-in, `tk close <id> --reason done|wontdo|duplicate|superseded [-m text] [--ref id] [--force]`: refuses open blockers, open children and (for won't-do / duplicate / superseded) open dependents, writes the `Closed: <resolution>` note, prints the tickets that became ready and the last-open-child hint; requires ticket-impact; `tk super close` bypasses it
```

- [ ] **Step 5: scripts/publish-aur.sh**

Replace

```bash
    case "$plugin_name" in
        query|migrate-beads) extra_deps="'jq'" ;;
    esac
```

with

```bash
    case "$plugin_name" in
        query|migrate-beads) extra_deps="'jq'" ;;
        close) extra_deps="'ticket-impact'" ;;
    esac
```

- [ ] **Step 6: scripts/publish-homebrew.sh**

In `generate_plugin_formula`, after the line

```bash
    local class_name="Ticket$(echo "$plugin_name" | sed -r 's/(^|-)(\w)/\U\2/g')"
```

add

```bash

    # Plugins that call another plugin depend on its formula
    local extra_deps=""
    case "$plugin_name" in
        close) extra_deps=$'\n  depends_on "ticket-impact"' ;;
    esac
```

and in the heredoc of the same function replace the line

```
  depends_on "ticket-core"
```

with

```
  depends_on "ticket-core"$extra_deps
```

Only the occurrence inside `generate_plugin_formula` changes (the first one in the file, followed by a blank line and `def install` with `bin.install "plugins/ticket-$plugin_name"`); the `ticket-extras` and `ticket` meta-formulas further down keep their lines.

- [ ] **Step 7: Verify the scripts**

Run: `bash -n scripts/publish-aur.sh && bash -n scripts/publish-homebrew.sh && echo ok`
Expected: `ok`

Run: `grep -n 'ticket-impact' scripts/publish-aur.sh scripts/publish-homebrew.sh`
Expected: one line in each file.

Run: `grep -c 'depends_on "ticket-core"\$extra_deps' scripts/publish-homebrew.sh`
Expected: `1`

- [ ] **Step 8: skills/managing-tk-tickets/SKILL.md - four minimal edits**

The full rewrite is `tic-x75b`; these edits only keep the skill from contradicting the tool. The manual path stays as the fallback, because without the plugin the built-in `tk close` silently ignores `--reason`.

Edit 1, in "tk facts that bite". Replace

```
`tk close` has no guards (closes blocked tickets and parents with open children, records no reason).
```

with

```
The built-in close (`tk super close`, `tk status <id> closed`) has no guards (closes blocked tickets and parents with open children, records no reason); the `ticket-close` plugin makes `tk close` guarded - `tk help` lists `close` under Plugins when it is installed.
```

Edit 2, Closing step 4. Replace

```
4. `tk add-note <id> "Closed: done - <one line: what was delivered>"`, then `tk close <id>`.
```

with

```
4. `tk close <id> --reason done -m "<one line: what was delivered>"` - writes the `Closed: done - ...` note and prints what became ready. A refusal means step 1 was skipped; do not answer it with `--force`. No `ticket-close` plugin: `tk add-note <id> "Closed: done - <...>"`, then `tk close <id>`.
```

Edit 3, the note-prefix line. Replace

```
Note prefixes (grep `^Closed: `): `Closed: done - ...` | `Closed: won't do - <why>` | `Closed: duplicate of <id>` | `Closed: superseded by <id>`.
```

with

```
Note prefixes (grep `^Closed: `), written by `tk close --reason done|wontdo|duplicate|superseded [-m "<text>"] [--ref <id>]`: `Closed: done - ...` | `Closed: won't do - <why>` | `Closed: duplicate of <id>` | `Closed: superseded by <id>`.
```

Edit 4, the "Won't do / duplicate / superseded" paragraph. Replace

```
settle every **Blocking** ticket BEFORE `tk close` - afterwards it is already falsely ready.
```

with

```
settle every **Blocking** ticket BEFORE `tk close` - afterwards it is already falsely ready (`tk close --reason wontdo|duplicate|superseded` refuses while open dependents exist; settle them, do not `--force`).
```

- [ ] **Step 9: Verify the docs against the tool**

Run: `PATH="$PWD/plugins:$PATH" ./ticket help | grep -n 'close'`
Expected: the built-in `close <id>` line and, under the plugins list, `close` with the description `Guarded close: refuse unsafe closes, record the reason, report what got unblocked`.

Run: `grep -c 'ticket-close' README.md plugins/README.md CHANGELOG.md skills/managing-tk-tickets/SKILL.md`
Expected: every file reports at least 1.

Run: `grep -n 'close' pkg/extras.txt`
Expected: no output (exit 1).

Run: `make test 2>&1 | tail -4`
Expected: `256 scenarios passed, 0 failed`.

- [ ] **Step 10: Commit**

```bash
git add README.md plugins/README.md CHANGELOG.md scripts/publish-aur.sh scripts/publish-homebrew.sh skills/managing-tk-tickets/SKILL.md
git commit -m "docs: ticket-close usage, packaging dependency and skill wording (tic-yxrw)"
```

---

### Task 5: Acceptance check and hand-over

**Files:**
- Modify: `.tickets/tic-yxrw.md` (only through `tk`, only after the user's yes)

**Interfaces:**
- Consumes: everything above.
- Produces: the evidence the user needs to approve the close.

- [ ] **Step 1: Walk the acceptance criteria of `tic-yxrw` with evidence**

Run `./ticket show tic-yxrw` and, for every criterion, name the scenario or file that satisfies it:

| Criterion | Evidence |
|---|---|
| refuses with open blocker | scenario "Open blocker refuses the close" |
| refuses with open child | "Open child refuses the close" |
| `--force` overrides | "Force closes despite blocker and child and records it" |
| missing `--reason` fails | "Missing --reason is a usage error" |
| note prefix for each reason | "Done note", "Won't-do note", "Duplicate note", "Superseded note with a text" |
| wontdo with open dependents refused | "Won't-do close with an open dependent is refused" |
| unblocked tickets printed | "Unblocked dependents are reported, still blocked ones are not" |
| parent hint printed | "Parent hint when the last open child closes" |
| `tk super close` still bypasses | "tk super close bypasses the guard" |
| `make test` passes | output of `make test 2>&1 | tail -4` from this step, run fresh |
| README, plugins/README, CHANGELOG updated | Task 4 commit |
| metadata present | `head -3 plugins/ticket-close` |
| not in `pkg/extras.txt` | `grep -n close pkg/extras.txt` prints nothing |

- [ ] **Step 2: Forecast the close**

Run: `PATH="$PWD/plugins:$PATH" ./ticket impact tic-yxrw`
Report to the user which of `tic-o862` and `tic-x75b` really become ready (both have other open blockers at the time of writing, so the expected answer is "none") and that `tic-sa3b` keeps other open children.

- [ ] **Step 3: STOP AND ASK**

Show the evidence table and the forecast, and ask whether to close `tic-yxrw`. Do not close on "commit it" or on silence. Follow the `managing-tk-tickets` skill (Closing, step 3).

- [ ] **Step 4: After an explicit yes - close with the new plugin and commit**

```bash
PATH="$PWD/plugins:$PATH" ./ticket close tic-yxrw --reason done -m "plugins/ticket-close 1.0.0: guarded tk close with --reason, Closed: note, unblock report"
git add .tickets/
git commit -m "chore: close tic-yxrw (ticket-close guard)"
```

Then integrate the branch with superpowers:finishing-a-development-branch. The `tic-mwhy` branch edits the same places in `README.md`, `plugins/README.md`, `CHANGELOG.md` and `SKILL.md`; whichever merges second resolves plain textual conflicts by keeping both sides.

---

## Appendix: final `plugins/ticket-close`

After Task 3 the file must be byte-identical to this listing:

```bash
#!/usr/bin/env bash
# tk-plugin: Guarded close: refuse unsafe closes, record the reason, report what got unblocked
# tk-plugin-version: 1.0.0
set -euo pipefail

usage() {
    echo "Usage: tk close <id> --reason done|wontdo|duplicate|superseded [-m <text>] [--ref <id>] [--force]"
    echo "  --reason <r>  resolution; done and wontdo require -m, duplicate and superseded require --ref"
    echo "  -m <text>     what was delivered / why it will not be done; written into the Closed: note"
    echo "  --ref <id>    the ticket this one duplicates or is superseded by"
    echo "  --force       close despite open blockers, children or dependents; recorded in the note"
    echo "Bypass the guard: tk super close <id>"
}

die_usage() {
    echo "Error: $1" >&2
    usage >&2
    exit 2
}

if [[ -z "${TK_SCRIPT:-}" ]]; then
    echo "Error: TK_SCRIPT is not set; run this plugin through tk" >&2
    exit 2
fi

reason="" text="" ref="" have_text=0 have_ref=0 force=0
ids=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --reason)
            [[ $# -ge 2 ]] || die_usage "--reason requires a value"
            reason="$2"; shift 2 ;;
        --reason=*) reason="${1#--reason=}"; shift ;;
        -m)
            [[ $# -ge 2 ]] || die_usage "-m requires a text"
            text="$2"; have_text=1; shift 2 ;;
        --ref)
            [[ $# -ge 2 ]] || die_usage "--ref requires a ticket ID"
            ref="$2"; have_ref=1; shift 2 ;;
        --ref=*) ref="${1#--ref=}"; have_ref=1; shift ;;
        --force) force=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; while [[ $# -gt 0 ]]; do ids+=("$1"); shift; done ;;
        -*) die_usage "unknown option: $1" ;;
        *) ids+=("$1"); shift ;;
    esac
done

[[ ${#ids[@]} -eq 1 ]] || die_usage "expected exactly one <id>"
[[ -n "$reason" ]] || die_usage "--reason is required"
case "$reason" in
    done|wontdo)
        [[ $have_ref -eq 0 ]] || die_usage "--ref is only valid with --reason duplicate|superseded"
        [[ $have_text -eq 1 ]] || die_usage "--reason $reason requires -m <text>"
        [[ -n "${text//[[:space:]]/}" ]] || die_usage "-m must not be empty"
        ;;
    duplicate|superseded)
        [[ $have_ref -eq 1 && -n "${ref//[[:space:]]/}" ]] || die_usage "--reason $reason requires --ref <id>"
        [[ $have_text -eq 0 || -n "${text//[[:space:]]/}" ]] || die_usage "-m must not be empty"
        ;;
    *) die_usage "invalid --reason '$reason' (done|wontdo|duplicate|superseded)" ;;
esac

if [[ -z "${TICKETS_DIR:-}" || ! -d "$TICKETS_DIR" ]]; then
    echo "Error: no .tickets directory found (searched parent directories)" >&2
    exit 2
fi

# Full ID on stdout. Core resolves it (exact or partial) and prints its own
# errors; the output is captured first so pipefail never sees a SIGPIPE.
resolve_id() {
    local out
    out=$("$TK_SCRIPT" super show "$1") || return 1
    awk '/^id:/ && !done { print $2; done = 1 }' <<< "$out"
}

id=$(resolve_id "${ids[0]}") || exit 1
if [[ $have_ref -eq 1 ]]; then
    ref=$(resolve_id "$ref") || exit 1
    if [[ "$ref" == "$id" ]]; then
        if [[ "$reason" == "duplicate" ]]; then
            echo "Error: $id cannot be a duplicate of itself" >&2
        else
            echo "Error: $id cannot be superseded by itself" >&2
        fi
        exit 1
    fi
fi

if ! command -v ticket-impact >/dev/null 2>&1 && ! command -v tk-impact >/dev/null 2>&1; then
    echo "Error: tk close needs the ticket-impact plugin on PATH" >&2
    echo "Use 'tk super close' to bypass the guard" >&2
    exit 1
fi

# Taken before the close: tk impact computes every fact as if the ticket were
# already closed, so this is the guard input and the forecast for the report.
facts=$("$TK_SCRIPT" impact --porcelain "$id") || exit $?

if [[ "$(awk '$1 == "status" { print $2 }' <<< "$facts")" == "closed" ]]; then
    echo "$id is already closed"
    exit 0
fi

# IDs (second field) of the porcelain lines of the given kinds, joined with ", "
facts_of() {
    awk -v kinds=" $* " '
        index(kinds, " " $1 " ") { out = out (out == "" ? "" : ", ") $2 }
        END { print out }
    ' <<< "$facts"
}

blockers=$(facts_of blocker)
children=$(facts_of child)
dependents=""
[[ "$reason" == "done" ]] || dependents=$(facts_of ready blocked)

if [[ -n "$blockers$children$dependents" ]]; then
    if [[ $force -eq 0 ]]; then
        [[ -z "$blockers" ]] || echo "Error: $id has open blockers: $blockers" >&2
        [[ -z "$children" ]] || echo "Error: $id has open children: $children" >&2
        [[ -z "$dependents" ]] || echo "Error: $id has open dependents that would see it as resolved: $dependents (settle them first: tk undep / tk dep)" >&2
        echo "Use --force to close anyway, or 'tk super close' to bypass the guard" >&2
        exit 1
    fi
    [[ -z "$blockers" ]] || echo "Warning: closing $id with open blockers: $blockers" >&2
    [[ -z "$children" ]] || echo "Warning: closing $id with open children: $children" >&2
    [[ -z "$dependents" ]] || echo "Warning: closing $id with open dependents: $dependents" >&2
fi

case "$reason" in
    done) note="Closed: done - $text" ;;
    wontdo) note="Closed: won't do - $text" ;;
    duplicate) note="Closed: duplicate of $ref" ;;
    superseded) note="Closed: superseded by $ref" ;;
esac
if [[ "$reason" != "done" && "$reason" != "wontdo" && $have_text -eq 1 ]]; then
    note="$note - $text"
fi
first_line="$note"

forced=""
[[ -z "$blockers" ]] || forced="open blockers $blockers"
[[ -z "$children" ]] || forced="${forced:+$forced; }open children $children"
[[ -z "$dependents" ]] || forced="${forced:+$forced; }open dependents $dependents"
[[ -z "$forced" ]] || note="$note"$'\n'"Forced: $forced"

"$TK_SCRIPT" super add-note "$id" "$note" >/dev/null || exit 1
if ! "$TK_SCRIPT" super close "$id"; then
    echo "Error: note written but tk super close failed" >&2
    exit 1
fi
echo "Note: $first_line"

ready=$(facts_of ready)
if [[ -n "$ready" ]]; then
    echo "Now ready: $ready"
else
    echo "Nothing became ready"
fi
parent=$(facts_of last-child)
[[ -z "$parent" ]] || echo "Last open child of $parent closed - consider closing $parent"
```
