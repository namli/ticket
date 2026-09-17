# ticket-start / ticket-reopen Guards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two plugins, `plugins/ticket-start` and `plugins/ticket-reopen`, that shadow the built-in `tk start` / `tk reopen`: start refuses blocked and closed tickets, reopen requires a reason, writes the `Reopened:` note and reports re-blocked dependents.

**Architecture:** Each plugin is one self-contained bash file with no graph logic of its own. The full ID comes from `"$TK_SCRIPT" super show`, every graph fact from one `"$TK_SCRIPT" impact --porcelain <id>` call made before any write (`status`, `blocker`, `ready` lines), and every write goes through `"$TK_SCRIPT" super start|status|add-note`. The plugins never edit a ticket file.

**Tech Stack:** bash, POSIX awk, the `ticket-impact` plugin (already in `plugins/`); tests are Behave features run with `make test` (`uv run --with behave behave`).

**Spec:** `docs/superpowers/specs/2026-09-17-ticket-start-reopen-guard-design.md` - read it first; this plan argues from it.

## Global Constraints

- Working directory for every command: `/home/namli/www/ticket/.claude/worktrees/tic-6rw0-guarded-start-reopen` (branch `worktree-tic-6rw0-guarded-start-reopen`). Never `cd` to the main checkout.
- No changes to the core `ticket` script. No changes to `plugins/ticket-impact` (stays 1.0.0).
- Plugin metadata in the first lines, exactly: `# tk-plugin: <description>` and `# tk-plugin-version: 1.0.0`. Files are executable (`chmod +x`).
- The plugins are NOT added to `pkg/extras.txt` (new plugins, not core extractions).
- Exit codes: 0 status changed or nothing to change; 1 guard refused / bad ID / `ticket-impact` missing / delegated built-in failed; 2 usage error or no tickets directory.
- Message texts are part of the contract - copy them verbatim from this plan (they are asserted by the scenarios and quoted in the docs).
- awk must stay POSIX: no gawk extensions, bracket expressions written as `[][ \t]` style (see `tic-xj6g`). The code below uses only `$1 == kind`, `printf`, `print`, `exit`.
- New feature files use ONLY existing step definitions from `features/steps/ticket_steps.py`. Do not add steps (the `tic-mwhy` branch adds one to the same file; avoid the conflict).
- In feature files a command is written `When I run "ticket ..."`; arguments with spaces use single quotes inside the double-quoted command (`-m 'two words'`). `the output should contain` / `should not contain` look at stdout+stderr; `the output should be` / `the output line N` look at stdout only; `the error output ...` looks at stderr only.
- `features/environment.py` puts `plugins/` on `PATH` for the whole suite, so once a plugin exists `ticket start` / `ticket reopen` in ANY feature reaches the guard. Core scenarios of a shadowed command go through `ticket super <cmd>`.
- Commits: conventional prefix + `(tic-6rw0)` suffix, e.g. `feat: add ticket-start guard plugin (tic-6rw0)`. NO attribution trailers of any kind (`Co-Authored-By`, "Generated with") - the message ends with its last line of real content.
- Ticket state (`.tickets/`) changes only through `tk`, and only where this plan says so. `tic-6rw0` is already `in_progress`. Do NOT close it - Task 4 ends with a STOP that hands the close decision to the user.
- `gh` is not needed by this plan. If you do use it: `GH_CONFIG_DIR=$HOME/.config/gh-namli gh ...` only.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `plugins/ticket-start` | create | Guarded `tk start`. |
| `plugins/ticket-reopen` | create | Guarded `tk reopen`. |
| `features/ticket_start_guard.feature` | create | 23 scenarios for `ticket-start`. |
| `features/ticket_reopen_guard.feature` | create | 24 scenarios for `ticket-reopen`. |
| `features/ticket_status.feature` | modify | "Start command" and "Reopen command" scenarios go through `super`. |
| `README.md` | modify | Usage block lines + official-plugins paragraph. |
| `plugins/README.md` | modify | `ticket-start` and `ticket-reopen` sections. |
| `CHANGELOG.md` | modify | Two `### Plugins` entries. |
| `scripts/publish-aur.sh`, `scripts/publish-homebrew.sh` | modify | Package dependency on `ticket-impact`. |
| `skills/managing-tk-tickets/SKILL.md`, `skills/managing-tk-tickets/editing.md` | modify | Minimal edits so the skill matches the tools. |

Baseline before Task 1: `make test` -> `210 scenarios passed, 0 failed`.

---

### Task 1: `ticket-start` plugin

**Files:**
- Create: `features/ticket_start_guard.feature`
- Create: `plugins/ticket-start`
- Modify: `features/ticket_status.feature` (scenario "Start command sets status to in_progress")

**Interfaces:**
- Consumes: `"$TK_SCRIPT" super show <id>` (front matter `id:` line), `"$TK_SCRIPT" impact --porcelain <id>` (`status <s>` and `blocker <id>` lines, sorted by ID), `"$TK_SCRIPT" super add-note <id> <text>`, `"$TK_SCRIPT" super start <id>` (prints `Updated <id> -> in_progress`). `TK_SCRIPT` and `TICKETS_DIR` are exported by the `ticket` dispatcher.
- Produces: the command `tk start <id> [--force]` with the messages asserted below. Task 3 documents them; nothing else depends on this file.

- [ ] **Step 1: Write the failing feature**

Create `features/ticket_start_guard.feature` with exactly this content:

```gherkin
Feature: Guarded start
  As an agent working from the ticket graph
  I want tk start to refuse blocked and closed tickets
  So that work never begins on a ticket whose blockers are still open

  Background:
    Given a clean tickets directory

  # --- Guard: open blockers ---

  Scenario: Open blocker refuses the start
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And the error output should contain "Error: sg-0001 has open blockers: sg-0002"
    And the error output should contain "Use --force to start anyway, or 'tk super start' to bypass the guard"
    And the output should be empty
    And ticket "sg-0001" should have field "status" with value "open"

  Scenario: Several blockers are listed in ID order
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker B"
    And a ticket exists with ID "sg-0003" and title "Blocker C"
    And ticket "sg-0001" depends on "sg-0003"
    And ticket "sg-0001" depends on "sg-0002"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And the error output should contain "open blockers: sg-0002, sg-0003"

  Scenario: In-progress blocker refuses the start
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    And ticket "sg-0002" has status "in_progress"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And ticket "sg-0001" should have field "status" with value "open"

  Scenario: Dangling dependency refuses the start
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And ticket "sg-0001" depends on "sg-gone"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And the error output should contain "open blockers: sg-gone"

  Scenario: Closed blocker does not refuse
    Given a ticket exists with ID "sg-0001" and title "Unblocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    And ticket "sg-0002" has status "closed"
    When I run "ticket start sg-0001"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"
    And the error output should be empty
    And ticket "sg-0001" should have field "status" with value "in_progress"

  Scenario: Ticket without dependencies starts
    Given a ticket exists with ID "sg-0001" and title "Free work"
    When I run "ticket start sg-0001"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"
    And ticket "sg-0001" should have field "status" with value "in_progress"

  # --- --force ---

  Scenario: --force starts a blocked ticket and records the override
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    When I run "ticket start sg-0001 --force"
    Then the exit code should be 0
    And the error output should contain "Warning: starting sg-0001 with open blockers: sg-0002"
    And the output line 1 should contain "Updated sg-0001 -> in_progress"
    And the output line 2 should contain "Note: Forced start: open blockers sg-0002"
    And ticket "sg-0001" should have field "status" with value "in_progress"
    And ticket "sg-0001" should contain "Forced start: open blockers sg-0002"
    And ticket "sg-0001" should contain a timestamp in notes

  Scenario: --force before the ID
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    When I run "ticket start --force sg-0001"
    Then the exit code should be 0
    And ticket "sg-0001" should have field "status" with value "in_progress"

  Scenario: --force without blockers writes no note
    Given a ticket exists with ID "sg-0001" and title "Free work"
    When I run "ticket start sg-0001 --force"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"
    And the error output should be empty
    When I run "ticket show sg-0001"
    Then the output should not contain "Forced start"

  # --- Closed and already started tickets ---

  Scenario: Closed ticket is refused and pointed to tk reopen
    Given a ticket exists with ID "sg-0001" and title "Done work"
    And ticket "sg-0001" has status "closed"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And the error output should contain "Error: sg-0001 is closed - use 'tk reopen sg-0001 -m <reason> --in-progress'"
    And the output should be empty
    And ticket "sg-0001" should have field "status" with value "closed"

  Scenario: --force does not start a closed ticket
    Given a ticket exists with ID "sg-0001" and title "Done work"
    And ticket "sg-0001" has status "closed"
    When I run "ticket start sg-0001 --force"
    Then the exit code should be 1
    And the error output should contain "sg-0001 is closed"
    And ticket "sg-0001" should have field "status" with value "closed"

  Scenario: Ticket already in progress is left alone
    Given a ticket exists with ID "sg-0001" and title "Running work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    And ticket "sg-0001" has status "in_progress"
    When I run "ticket start sg-0001"
    Then the exit code should be 0
    And the output should be "sg-0001 is already in progress"
    And the error output should be empty

  # --- Usage ---

  Scenario: Missing ID prints usage
    When I run "ticket start"
    Then the exit code should be 2
    And the error output should contain "Error: expected exactly one <id>"
    And the error output should contain "Usage: tk start <id> [--force]"

  Scenario: Two IDs are rejected
    Given a ticket exists with ID "sg-0001" and title "First"
    And a ticket exists with ID "sg-0002" and title "Second"
    When I run "ticket start sg-0001 sg-0002"
    Then the exit code should be 2
    And the error output should contain "Error: expected exactly one <id>"
    And ticket "sg-0001" should have field "status" with value "open"
    And ticket "sg-0002" should have field "status" with value "open"

  Scenario: Unknown flag is rejected
    Given a ticket exists with ID "sg-0001" and title "First"
    When I run "ticket start --bogus sg-0001"
    Then the exit code should be 2
    And the error output should contain "Error: unknown option: --bogus"
    And ticket "sg-0001" should have field "status" with value "open"

  Scenario: Double dash ends option parsing
    Given a ticket exists with ID "sg-0001" and title "Free work"
    When I run "ticket start -- sg-0001"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"

  Scenario: --help prints usage on stdout
    When I run "ticket start --help"
    Then the exit code should be 0
    And the output should contain "Usage: tk start <id> [--force]"
    And the error output should be empty

  Scenario: No tickets directory is an environment error
    Given the tickets directory does not exist
    When I run "ticket start sg-0001"
    Then the exit code should be 2
    And the error output should contain "no .tickets directory found"

  # --- IDs ---

  Scenario: Partial ID is resolved to the full ID
    Given a ticket exists with ID "sg-0001" and title "Free work"
    When I run "ticket start 0001"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"

  Scenario: Unknown ID fails with core's message
    Given a ticket exists with ID "sg-0001" and title "First"
    When I run "ticket start nope"
    Then the exit code should be 1
    And the error output should contain "Error: ticket 'nope' not found"

  Scenario: Ambiguous ID fails with core's message
    Given a ticket exists with ID "sg-0001" and title "First"
    And a ticket exists with ID "sg-0002" and title "Second"
    When I run "ticket start sg-"
    Then the exit code should be 1
    And the error output should contain "Error: ambiguous ID 'sg-' matches multiple tickets"
    And ticket "sg-0001" should have field "status" with value "open"

  # --- Bypass and help ---

  Scenario: tk super start bypasses the guard
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    When I run "ticket super start sg-0001"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"

  Scenario: tk help lists the start plugin
    When I run "ticket help"
    Then the exit code should be 0
    And the output should contain "Guarded start: refuse blocked and closed tickets"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `uv run --with behave behave features/ticket_start_guard.feature 2>&1 | tail -4`
Expected: `7 scenarios passed, 16 failed` - the built-in `start` has no guard, no `--force`, no usage errors with exit 2. If the counts differ by one or two, read the failures: every failure must be a missing guard behaviour, not a typo in the feature (`undefined step` anywhere means the feature text was altered - fix it).

- [ ] **Step 3: Write the plugin**

Create `plugins/ticket-start` with exactly this content:

```bash
#!/usr/bin/env bash
# tk-plugin: Guarded start: refuse blocked and closed tickets
# tk-plugin-version: 1.0.0
set -euo pipefail

usage() {
    echo "Usage: tk start <id> [--force]"
    echo "  --force  start although the ticket has open blockers"
    echo "Bypass the guard: tk super start <id>"
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

force=0
ids=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) force=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; while [[ $# -gt 0 ]]; do ids+=("$1"); shift; done ;;
        -*) die_usage "unknown option: $1" ;;
        *) ids+=("$1"); shift ;;
    esac
done

[[ ${#ids[@]} -eq 1 ]] || die_usage "expected exactly one <id>"

if [[ -z "${TICKETS_DIR:-}" || ! -d "$TICKETS_DIR" ]]; then
    echo "Error: no .tickets directory found (searched parent directories)" >&2
    exit 2
fi

# Full ID on stdout; core resolves it, so partial IDs and error texts match every other command
resolve_id() {
    local out
    out=$("$TK_SCRIPT" super show "$1") || return 1
    awk '/^id:/ && !done { print $2; done = 1 }' <<< "$out"
}

# IDs (second field) of the porcelain lines of one kind, joined with ", "
facts_of() {
    awk -v kind="$1" '$1 == kind { printf "%s%s", sep, $2; sep = ", " }' <<< "$facts"
}

id=$(resolve_id "${ids[0]}") || exit 1

if ! command -v ticket-impact >/dev/null 2>&1 && ! command -v tk-impact >/dev/null 2>&1; then
    echo "Error: tk start needs the ticket-impact plugin on PATH" >&2
    echo "Use 'tk super start' to bypass the guard" >&2
    exit 1
fi

# One read, before any write: status and blocker lines do not depend on the target's status
facts=$("$TK_SCRIPT" impact --porcelain "$id") || exit $?
status=$(awk '$1 == "status" { print $2; exit }' <<< "$facts")
blockers=$(facts_of blocker)

if [[ "$status" == "closed" ]]; then
    # --force does not apply: starting a closed ticket is a reopen without a reason
    echo "Error: $id is closed - use 'tk reopen $id -m <reason> --in-progress'" >&2
    exit 1
fi

if [[ "$status" == "in_progress" ]]; then
    echo "$id is already in progress"
    exit 0
fi

note=""
if [[ -n "$blockers" ]]; then
    if [[ $force -eq 0 ]]; then
        echo "Error: $id has open blockers: $blockers" >&2
        echo "Use --force to start anyway, or 'tk super start' to bypass the guard" >&2
        exit 1
    fi
    echo "Warning: starting $id with open blockers: $blockers" >&2
    note="Forced start: open blockers $blockers"
    "$TK_SCRIPT" super add-note "$id" "$note" >/dev/null || exit 1
fi

if ! "$TK_SCRIPT" super start "$id"; then
    [[ -z "$note" ]] || echo "Error: note written but tk super start failed" >&2
    exit 1
fi
[[ -z "$note" ]] || echo "Note: $note"
```

Then: `chmod +x plugins/ticket-start`

Why it is shaped this way (do not "improve" these):
- Arguments are validated before anything is resolved or read, so a usage error never depends on the tickets.
- `resolve_id` captures `super show` output first and lets awk read it to the end - with `set -o pipefail` an early-exiting reader would turn into a SIGPIPE failure.
- The `closed` check comes before the `--force` handling on purpose: `--force` must not start a closed ticket.
- The forced note is written BEFORE the status change (so a failed note never leaves a forced start without a trace) but reported AFTER the built-in's `Updated` line.

- [ ] **Step 4: Run the feature to verify it passes**

Run: `uv run --with behave behave features/ticket_start_guard.feature 2>&1 | tail -4`
Expected: `23 scenarios passed, 0 failed, 0 skipped`

- [ ] **Step 5: Route the core start scenario through `super`**

In `features/ticket_status.feature`, scenario "Start command sets status to in_progress", change

```gherkin
    When I run "ticket start test-0001"
```

to

```gherkin
    When I run "ticket super start test-0001"
```

Nothing else in that scenario changes. It tests the built-in; without `super` it would now exercise the plugin instead.

- [ ] **Step 6: Run the whole suite**

Run: `make test 2>&1 | tail -4`
Expected: `16 features passed, 0 failed` and `233 scenarios passed, 0 failed, 0 skipped`

- [ ] **Step 7: Commit**

```bash
git add plugins/ticket-start features/ticket_start_guard.feature features/ticket_status.feature
git commit -m "feat: add ticket-start guard plugin (tic-6rw0)"
```

---

### Task 2: `ticket-reopen` plugin

**Files:**
- Create: `features/ticket_reopen_guard.feature`
- Create: `plugins/ticket-reopen`
- Modify: `features/ticket_status.feature` (scenario "Reopen command sets status to open")

**Interfaces:**
- Consumes: `"$TK_SCRIPT" super show <id>`, `"$TK_SCRIPT" impact --porcelain <id>` (`status`, `blocker <id>`, `ready <id>` lines - on a closed target the `ready` lines are exactly the dependents a reopen re-blocks), `"$TK_SCRIPT" super add-note <id> <text>` (the text may contain a newline), `"$TK_SCRIPT" super status <id> open|in_progress` (prints `Updated <id> -> <status>`).
- Produces: the command `tk reopen <id> -m <reason> [--in-progress] [--force]` with the messages asserted below. Independent of Task 1: the two plugins share no code and do not call each other (the `resolve_id` / `facts_of` / `die_usage` helpers are intentionally repeated in each file - see the spec, Architecture).

- [ ] **Step 1: Write the failing feature**

Create `features/ticket_reopen_guard.feature` with exactly this content:

```gherkin
Feature: Guarded reopen
  As an agent working from the ticket graph
  I want tk reopen to record why a ticket came back and what it re-blocked
  So that a reopen never silently changes which tickets are ready

  Background:
    Given a clean tickets directory

  # --- Reason is required ---

  Scenario: Reopen without -m is a usage error
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001"
    Then the exit code should be 2
    And the error output should contain "Error: -m <reason> is required"
    And the error output should contain "Usage: tk reopen <id> -m <reason> [--in-progress] [--force]"
    And ticket "rg-0001" should have field "status" with value "closed"
    When I run "ticket show rg-0001"
    Then the output should not contain "Reopened:"

  Scenario: Empty reason is a usage error
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m ''"
    Then the exit code should be 2
    And the error output should contain "Error: -m must not be empty"
    And ticket "rg-0001" should have field "status" with value "closed"

  Scenario: -m without a value is a usage error
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m"
    Then the exit code should be 2
    And the error output should contain "Error: -m requires a reason"
    And ticket "rg-0001" should have field "status" with value "closed"

  # --- Note and status ---

  Scenario: Reopen writes the note and sets open
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'parser regression in nested lists'"
    Then the exit code should be 0
    And the output line 1 should contain "Updated rg-0001 -> open"
    And the output line 2 should contain "Note: Reopened: parser regression in nested lists"
    And the output line 3 should contain "Nothing was re-blocked"
    And the error output should be empty
    And ticket "rg-0001" should have field "status" with value "open"
    And ticket "rg-0001" should contain "Reopened: parser regression in nested lists"
    And ticket "rg-0001" should contain a timestamp in notes

  Scenario: --in-progress sets in_progress
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'commit abandoned' --in-progress"
    Then the exit code should be 0
    And the output line 1 should contain "Updated rg-0001 -> in_progress"
    And ticket "rg-0001" should have field "status" with value "in_progress"
    And ticket "rg-0001" should contain "Reopened: commit abandoned"

  Scenario: Flags before the ID
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen --in-progress -m 'rework' rg-0001"
    Then the exit code should be 0
    And ticket "rg-0001" should have field "status" with value "in_progress"

  # --- Re-blocked report ---

  Scenario: Dependents whose only open blocker is the target are reported
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And a ticket exists with ID "rg-0002" and title "Waits only for 0001"
    And a ticket exists with ID "rg-0003" and title "Waits for 0001 and 0004"
    And a ticket exists with ID "rg-0004" and title "Other open blocker"
    And a ticket exists with ID "rg-0005" and title "Closed dependent"
    And a ticket exists with ID "rg-0006" and title "Also waits only for 0001"
    And ticket "rg-0001" has status "closed"
    And ticket "rg-0002" depends on "rg-0001"
    And ticket "rg-0003" depends on "rg-0001"
    And ticket "rg-0003" depends on "rg-0004"
    And ticket "rg-0005" depends on "rg-0001"
    And ticket "rg-0005" has status "closed"
    And ticket "rg-0006" depends on "rg-0001"
    When I run "ticket reopen rg-0001 -m 'regression'"
    Then the exit code should be 0
    And the output line 3 should contain "Re-blocked: rg-0002, rg-0006"
    And the output should not contain "rg-0003"
    And the output should not contain "rg-0005"

  # --- Guard: --in-progress with open blockers ---

  Scenario: --in-progress with an open blocker is refused
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And a ticket exists with ID "rg-0002" and title "Blocker"
    And ticket "rg-0001" depends on "rg-0002"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'rework' --in-progress"
    Then the exit code should be 1
    And the error output should contain "Error: rg-0001 has open blockers: rg-0002"
    And the error output should contain "Use --force to reopen as in_progress anyway, or reopen without --in-progress"
    And the output should be empty
    And ticket "rg-0001" should have field "status" with value "closed"
    When I run "ticket show rg-0001"
    Then the output should not contain "Reopened:"

  Scenario: --force overrides the blocker guard and records it
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And a ticket exists with ID "rg-0002" and title "Blocker"
    And ticket "rg-0001" depends on "rg-0002"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'rework' --in-progress --force"
    Then the exit code should be 0
    And the error output should contain "Warning: reopening rg-0001 as in_progress with open blockers: rg-0002"
    And the output line 1 should contain "Updated rg-0001 -> in_progress"
    And the output line 2 should contain "Note: Reopened: rework"
    And ticket "rg-0001" should have field "status" with value "in_progress"
    And ticket "rg-0001" should contain "Reopened: rework"
    And ticket "rg-0001" should contain "Forced: open blockers rg-0002"

  Scenario: Plain reopen with an open blocker is not refused
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And a ticket exists with ID "rg-0002" and title "Blocker"
    And ticket "rg-0001" depends on "rg-0002"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'rework'"
    Then the exit code should be 0
    And the error output should be empty
    And ticket "rg-0001" should have field "status" with value "open"
    When I run "ticket show rg-0001"
    Then the output should not contain "Forced:"

  Scenario: --force without a violation writes no Forced line
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'rework' --in-progress --force"
    Then the exit code should be 0
    And the error output should be empty
    And ticket "rg-0001" should have field "status" with value "in_progress"
    When I run "ticket show rg-0001"
    Then the output should not contain "Forced:"

  # --- Not closed ---

  Scenario: Open ticket has nothing to reopen
    Given a ticket exists with ID "rg-0001" and title "Open work"
    When I run "ticket reopen rg-0001 -m 'again'"
    Then the exit code should be 0
    And the output should be "rg-0001 is not closed (status: open) - nothing to reopen"
    When I run "ticket show rg-0001"
    Then the output should not contain "Reopened:"

  Scenario: In-progress ticket is not demoted to open
    Given a ticket exists with ID "rg-0001" and title "Running work"
    And ticket "rg-0001" has status "in_progress"
    When I run "ticket reopen rg-0001 -m 'again'"
    Then the exit code should be 0
    And the output should be "rg-0001 is not closed (status: in_progress) - nothing to reopen"
    And ticket "rg-0001" should have field "status" with value "in_progress"
    When I run "ticket show rg-0001"
    Then the output should not contain "Reopened:"

  # --- Usage ---

  Scenario: Missing ID prints usage
    When I run "ticket reopen -m 'x'"
    Then the exit code should be 2
    And the error output should contain "Error: expected exactly one <id>"

  Scenario: Two IDs are rejected
    Given a ticket exists with ID "rg-0001" and title "First"
    And a ticket exists with ID "rg-0002" and title "Second"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 rg-0002 -m 'x'"
    Then the exit code should be 2
    And the error output should contain "Error: expected exactly one <id>"
    And ticket "rg-0001" should have field "status" with value "closed"

  Scenario: Unknown flag is rejected
    Given a ticket exists with ID "rg-0001" and title "First"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'x' --bogus"
    Then the exit code should be 2
    And the error output should contain "Error: unknown option: --bogus"
    And ticket "rg-0001" should have field "status" with value "closed"

  Scenario: Double dash ends option parsing
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen -m 'rework' -- rg-0001"
    Then the exit code should be 0
    And ticket "rg-0001" should have field "status" with value "open"

  Scenario: --help prints usage on stdout
    When I run "ticket reopen --help"
    Then the exit code should be 0
    And the output should contain "Usage: tk reopen <id> -m <reason> [--in-progress] [--force]"
    And the error output should be empty

  Scenario: No tickets directory is an environment error
    Given the tickets directory does not exist
    When I run "ticket reopen rg-0001 -m 'x'"
    Then the exit code should be 2
    And the error output should contain "no .tickets directory found"

  # --- IDs ---

  Scenario: Partial ID is resolved and the full ID is reported
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen 0001 -m 'rework'"
    Then the exit code should be 0
    And the output line 1 should contain "Updated rg-0001 -> open"
    And ticket "rg-0001" should contain "Reopened: rework"

  Scenario: Unknown ID fails with core's message
    Given a ticket exists with ID "rg-0001" and title "First"
    When I run "ticket reopen nope -m 'x'"
    Then the exit code should be 1
    And the error output should contain "Error: ticket 'nope' not found"

  Scenario: Ambiguous ID fails with core's message
    Given a ticket exists with ID "rg-0001" and title "First"
    And a ticket exists with ID "rg-0002" and title "Second"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg- -m 'x'"
    Then the exit code should be 1
    And the error output should contain "Error: ambiguous ID 'rg-' matches multiple tickets"
    And ticket "rg-0001" should have field "status" with value "closed"

  # --- Bypass and help ---

  Scenario: tk super reopen bypasses the guard
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket super reopen rg-0001"
    Then the exit code should be 0
    And the output should be "Updated rg-0001 -> open"
    When I run "ticket show rg-0001"
    Then the output should not contain "Reopened:"

  Scenario: tk help lists the reopen plugin
    When I run "ticket help"
    Then the exit code should be 0
    And the output should contain "Guarded reopen: record the reason, report re-blocked dependents"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `uv run --with behave behave features/ticket_reopen_guard.feature 2>&1 | tail -4`
Expected: `4 scenarios passed, 20 failed` - the built-in `reopen` ignores `-m`, writes no note, prints no report. `undefined step` anywhere means the feature text was altered - fix it.

- [ ] **Step 3: Write the plugin**

Create `plugins/ticket-reopen` with exactly this content:

```bash
#!/usr/bin/env bash
# tk-plugin: Guarded reopen: record the reason, report re-blocked dependents
# tk-plugin-version: 1.0.0
set -euo pipefail

usage() {
    echo "Usage: tk reopen <id> -m <reason> [--in-progress] [--force]"
    echo "  -m <reason>    why the ticket is reopened; written as a 'Reopened:' note"
    echo "  --in-progress  set status in_progress instead of open"
    echo "  --force        with --in-progress: reopen although the ticket has open blockers"
    echo "Bypass the guard: tk super reopen <id>"
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

reason="" have_reason=0 in_progress=0 force=0
ids=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m)
            [[ $# -ge 2 ]] || die_usage "-m requires a reason"
            reason="$2"; have_reason=1; shift 2 ;;
        --in-progress) in_progress=1; shift ;;
        --force) force=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; while [[ $# -gt 0 ]]; do ids+=("$1"); shift; done ;;
        -*) die_usage "unknown option: $1" ;;
        *) ids+=("$1"); shift ;;
    esac
done

[[ ${#ids[@]} -eq 1 ]] || die_usage "expected exactly one <id>"
[[ $have_reason -eq 1 ]] || die_usage "-m <reason> is required"
[[ -n "${reason//[[:space:]]/}" ]] || die_usage "-m must not be empty"

if [[ -z "${TICKETS_DIR:-}" || ! -d "$TICKETS_DIR" ]]; then
    echo "Error: no .tickets directory found (searched parent directories)" >&2
    exit 2
fi

# Full ID on stdout; core resolves it, so partial IDs and error texts match every other command
resolve_id() {
    local out
    out=$("$TK_SCRIPT" super show "$1") || return 1
    awk '/^id:/ && !done { print $2; done = 1 }' <<< "$out"
}

# IDs (second field) of the porcelain lines of one kind, joined with ", "
facts_of() {
    awk -v kind="$1" '$1 == kind { printf "%s%s", sep, $2; sep = ", " }' <<< "$facts"
}

id=$(resolve_id "${ids[0]}") || exit 1

if ! command -v ticket-impact >/dev/null 2>&1 && ! command -v tk-impact >/dev/null 2>&1; then
    echo "Error: tk reopen needs the ticket-impact plugin on PATH" >&2
    echo "Use 'tk super reopen' to bypass the guard" >&2
    exit 1
fi

# One read, while the ticket is still closed: its 'ready' lines are what the reopen re-blocks
facts=$("$TK_SCRIPT" impact --porcelain "$id") || exit $?
status=$(awk '$1 == "status" { print $2; exit }' <<< "$facts")
blockers=$(facts_of blocker)
reblocked=$(facts_of ready)

if [[ "$status" != "closed" ]]; then
    echo "$id is not closed (status: ${status:-unknown}) - nothing to reopen"
    exit 0
fi

new_status="open"
note="Reopened: $reason"
if [[ $in_progress -eq 1 ]]; then
    new_status="in_progress"
    if [[ -n "$blockers" ]]; then
        if [[ $force -eq 0 ]]; then
            echo "Error: $id has open blockers: $blockers" >&2
            echo "Use --force to reopen as in_progress anyway, or reopen without --in-progress" >&2
            exit 1
        fi
        echo "Warning: reopening $id as in_progress with open blockers: $blockers" >&2
        note+=$'\n'"Forced: open blockers $blockers"
    fi
fi

"$TK_SCRIPT" super add-note "$id" "$note" >/dev/null || exit 1
if ! "$TK_SCRIPT" super status "$id" "$new_status"; then
    echo "Error: note written but tk super status failed" >&2
    exit 1
fi
echo "Note: ${note%%$'\n'*}"

if [[ -n "$reblocked" ]]; then
    echo "Re-blocked: $reblocked"
else
    echo "Nothing was re-blocked"
fi
```

Then: `chmod +x plugins/ticket-reopen`

Why it is shaped this way (do not "improve" these):
- The facts are read while the ticket is still closed; after the status change `tk impact` would still print the same `ready` lines, but the guard and the report must come from ONE read taken before any write.
- "Not closed" is checked before the blocker guard: an open or in-progress ticket exits 0 with no note even with `--in-progress --force`. This is what stops the built-in's silent demotion of `in_progress` to `open`.
- The blocker guard runs only with `--in-progress`. A plain reopen of a ticket with open blockers is fine - it simply lands in `tk blocked`.
- Note first, status second (the order the ticket prescribes). Only the first line of the note is echoed as `Note: ...`; the `Forced:` line is in the file and on stderr as the `Warning:`.

- [ ] **Step 4: Run the feature to verify it passes**

Run: `uv run --with behave behave features/ticket_reopen_guard.feature 2>&1 | tail -4`
Expected: `24 scenarios passed, 0 failed, 0 skipped`

- [ ] **Step 5: Route the core reopen scenario through `super`**

In `features/ticket_status.feature`, scenario "Reopen command sets status to open", change

```gherkin
    When I run "ticket reopen test-0001"
```

to

```gherkin
    When I run "ticket super reopen test-0001"
```

Without this the scenario now fails with exit 2 (`-m <reason> is required`).

- [ ] **Step 6: Run the whole suite**

Run: `make test 2>&1 | tail -4`
Expected: `17 features passed, 0 failed` and `257 scenarios passed, 0 failed, 0 skipped`

- [ ] **Step 7: Commit**

```bash
git add plugins/ticket-reopen features/ticket_reopen_guard.feature features/ticket_status.feature
git commit -m "feat: add ticket-reopen guard plugin (tic-6rw0)"
```

---

### Task 3: Documentation, packaging, skill

**Files:**
- Modify: `README.md` (usage block under "Official plugins (installed separately):", and the "**Official plugins** live in" paragraph)
- Modify: `plugins/README.md` (append two sections at the end of the file)
- Modify: `CHANGELOG.md` (`## [Unreleased]` -> `### Plugins`)
- Modify: `scripts/publish-aur.sh` (`generate_plugin_pkgbuild`), `scripts/publish-homebrew.sh` (`generate_plugin_formula`)
- Modify: `skills/managing-tk-tickets/SKILL.md`, `skills/managing-tk-tickets/editing.md`

**Interfaces:**
- Consumes: the CLI, messages and exit codes of Tasks 1 and 2, exactly as written there.
- Produces: nothing other tasks rely on.

- [ ] **Step 1: README usage block**

In `README.md`, inside the usage code block, directly after the line

```
  lint [--conventions] [--strict]    Check tickets for broken graph invariants
```

add:

```
  start <id> [--force]     Guarded start: refuse tickets with open blockers and closed tickets
  reopen <id> -m <reason> [--in-progress] [--force]
                           Guarded reopen: write a 'Reopened:' note, report re-blocked dependents
```

The core lines `start <id>` and `reopen <id>` higher in the block stay: they document the built-ins (`tk super start` / `tk super reopen`).

- [ ] **Step 2: README official-plugins paragraph**

In the paragraph that starts with `**Official plugins** live in`, insert this text directly before the sentence `None of them is part of \`ticket-extras\`:` (keep one space on each side):

```
`ticket-start` and `ticket-reopen` shadow the built-in `tk start` and `tk reopen` with guards: `tk start <id>` refuses a ticket with open blockers (`--force` overrides) and a closed ticket, and `tk reopen <id> -m <reason> [--in-progress]` writes a `Reopened:` note and reports which dependents went back to blocked. Both need `ticket-impact` on your PATH; `tk super start` / `tk super reopen` run the unguarded built-ins.
```

In the same paragraph's last sentence, extend both lists: `plugins/ticket-lint`, `plugins/ticket-find` and `plugins/ticket-impact` becomes `plugins/ticket-lint`, `plugins/ticket-find`, `plugins/ticket-impact`, `plugins/ticket-start` and `plugins/ticket-reopen`; and the `ticket-lint`, `ticket-find` and `ticket-impact` packages becomes the `ticket-lint`, `ticket-find`, `ticket-impact`, `ticket-start` and `ticket-reopen` packages.

- [ ] **Step 3: plugins/README.md sections**

Append to the end of `plugins/README.md` (after the `ticket-impact` section's last line, with one empty line before `## ticket-start`):

````markdown
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

Exit codes: 0 started or already in progress, 1 refused / ticket not found or ambiguous ID / `ticket-impact` missing, 2 usage error or no tickets directory.

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

Exit codes: 0 reopened or nothing to reopen, 1 refused / ticket not found or ambiguous ID / `ticket-impact` missing, 2 usage error (including a missing or empty `-m`) or no tickets directory.

The facts come from one `tk impact --porcelain` call taken while the ticket is still closed; the note and the status go through `tk super add-note` and `tk super status`. `tk super reopen <id>` runs the unguarded built-in.

Requires bash, POSIX awk and the `ticket-impact` plugin.
````

- [ ] **Step 4: CHANGELOG**

In `CHANGELOG.md`, under `## [Unreleased]` -> `### Plugins`, add after the `ticket-impact 1.0.0` line:

```markdown
- ticket-start 1.0.0: New plugin, shadows `tk start`: refuses a ticket with open blockers (`--force` overrides and writes a `Forced start:` note) and always refuses a closed ticket; needs `ticket-impact`; `tk super start` bypasses it
- ticket-reopen 1.0.0: New plugin, shadows `tk reopen`: `tk reopen <id> -m <reason> [--in-progress] [--force]` writes a `Reopened: <reason>` note, can restore `in_progress`, reports re-blocked dependents and leaves tickets that are not closed alone; needs `ticket-impact`; `tk super reopen` bypasses it
```

- [ ] **Step 5: AUR dependency**

In `scripts/publish-aur.sh`, function `generate_plugin_pkgbuild`, extend the existing `case`:

```bash
    case "$plugin_name" in
        query|migrate-beads) extra_deps="'jq'" ;;
        start|reopen) extra_deps="'ticket-impact'" ;;
    esac
```

- [ ] **Step 6: Homebrew dependency**

In `scripts/publish-homebrew.sh`, function `generate_plugin_formula`, add directly before the `cat > "$formula_dir/ticket-$plugin_name.rb" << EOF` line:

```bash
    # Plugins that call other plugins
    local extra_deps=""
    case "$plugin_name" in
        start|reopen) extra_deps=$'\n  depends_on "ticket-impact"' ;;
    esac

```

and inside the heredoc change the line

```
  depends_on "ticket-core"
```

to

```
  depends_on "ticket-core"$extra_deps
```

(Only the occurrence inside `generate_plugin_formula`; the meta-package formulas further down also contain `depends_on "ticket-core"` and stay untouched.)

- [ ] **Step 7: Verify the publish scripts**

Run each as a separate command:

```bash
bash -n scripts/publish-aur.sh
bash -n scripts/publish-homebrew.sh
```

Expected: no output, exit 0 for both.

Then create `formula-check.sh` in the session scratchpad directory (NOT in the repository):

```bash
#!/usr/bin/env bash
# Generate the Homebrew formulas for start and query from the real function and show their depends_on lines
set -euo pipefail
cd /home/namli/www/ticket/.claude/worktrees/tic-6rw0-guarded-start-reopen
VERSION=9.9.9 SHA256=abc REPO_ROOT=$PWD
source <(sed -n '/^find_plugin_symlinks() {/,/^}/p; /^parse_plugin_metadata() {/,/^}/p; /^generate_plugin_formula() {/,/^}/p' scripts/publish-homebrew.sh)
out=$(mktemp -d)
generate_plugin_formula start plugins/ticket-start "$out"
generate_plugin_formula query plugins/ticket-query "$out"
echo "== start"; grep -n 'depends_on' "$out/ticket-start.rb"
echo "== query"; grep -n 'depends_on' "$out/ticket-query.rb"
ruby -c "$out/ticket-start.rb" 2>/dev/null || echo "(ruby not installed: syntax check skipped)"
rm -rf "$out"
```

Run: `bash <scratchpad>/formula-check.sh`
Expected: under `== start` two lines, `depends_on "ticket-core"` and `depends_on "ticket-impact"`; under `== query` only `depends_on "ticket-core"`.

- [ ] **Step 8: Skill edits**

Five exact replacements. Each keeps the manual procedure as the fallback for a machine where the plugins are not installed (loud failure when they are missing is `tic-x75b`, not this ticket).

In `skills/managing-tk-tickets/SKILL.md`, section "tk facts that bite":

Replace
```
- `tk reopen` silently re-blocks dependents and sets `open`; restore work in progress with `tk status <id> in_progress`.
```
with
```
- `tk reopen <id> -m "<reason>" [--in-progress]` (ticket-reopen plugin) writes the `Reopened:` note and reports the re-blocked dependents. Without the plugin the built-in silently re-blocks dependents, sets `open` and records nothing: write the note yourself and restore work in progress with `tk status <id> in_progress`.
```

In the next bullet replace only its last sentence
```
`tk start` works on a blocked ticket - never do it.
```
with
```
`tk start` (ticket-start plugin) refuses blocked and closed tickets; the built-in starts anything - never start a blocked ticket, and use `--force` only when the user says so.
```

In "Closing" step 6 replace
```
Commit abandoned -> `tk status <id> in_progress` + note `Reopened: commit abandoned`.
```
with
```
Commit abandoned -> `tk reopen <id> -m "commit abandoned" --in-progress` (no plugin: `tk status <id> in_progress` + note `Reopened: commit abandoned`).
```

Replace the **Reopening** paragraph
```
**Reopening** a committed close: `tk add-note <id> "Reopened: <reason>"`, `tk reopen <id>`, `tk blocked` -> report what went back; commit with the rework.
```
with
```
**Reopening** a committed close: `tk reopen <id> -m "<reason>"` -> report its `Re-blocked:` line; commit with the rework. No plugin: `tk add-note <id> "Reopened: <reason>"`, `tk super reopen <id>`, `tk blocked` -> report what went back.
```

In `skills/managing-tk-tickets/editing.md` replace
```
**Closed tickets are not rewritten:** reopen with a `Reopened: <reason>` note, or open a new linked ticket.
```
with
```
**Closed tickets are not rewritten:** reopen with `tk reopen <id> -m "<reason>"` (no plugin: a `Reopened: <reason>` note + `tk super reopen <id>`), or open a new linked ticket.
```

Verify: `grep -n "tk reopen\|tk start" skills/managing-tk-tickets/SKILL.md skills/managing-tk-tickets/editing.md`
Expected: 5 matching lines, none containing the old texts `silently re-blocks dependents and sets` followed by `; restore` or `works on a blocked ticket`.

- [ ] **Step 9: Run the whole suite and commit**

Run: `make test 2>&1 | tail -4`
Expected: `257 scenarios passed, 0 failed, 0 skipped`

```bash
git add README.md plugins/README.md CHANGELOG.md scripts/publish-aur.sh scripts/publish-homebrew.sh skills/managing-tk-tickets/SKILL.md skills/managing-tk-tickets/editing.md
git commit -m "docs: document ticket-start and ticket-reopen, package deps, skill edits (tic-6rw0)"
```

---

### Task 4: Verification that the suite cannot express, and hand-off

**Files:**
- None in the repository. Scripts go to the session scratchpad directory.

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: the evidence for the close decision.

- [ ] **Step 1: Both features under busybox awk**

Create `bb-guards.sh` in the session scratchpad directory (NOT in the repository):

```bash
#!/usr/bin/env bash
# Run the two guard features with busybox awk shadowing the system awk
WT=/home/namli/www/ticket/.claude/worktrees/tic-6rw0-guarded-start-reopen
BB=$(mktemp -d)
ln -s "$(command -v busybox)" "$BB/awk"
export PATH="$BB:$PATH"
awk 2>&1 | head -1
cd "$WT" || exit 1
uv run --with behave behave features/ticket_start_guard.feature features/ticket_reopen_guard.feature 2>&1 | tail -4
rm -rf "$BB"
```

Run: `bash <scratchpad>/bb-guards.sh`
Expected: first line starts with `BusyBox`, then `47 scenarios passed, 0 failed, 0 skipped`. If `busybox` is not installed, record "busybox awk: not executed" for the report and continue.

- [ ] **Step 2: The "`ticket-impact` missing" branch, by hand**

The suite always has `plugins/` on `PATH`, so this branch has no scenario. Create `no-impact.sh` in the session scratchpad directory:

```bash
#!/usr/bin/env bash
# Guards on PATH without ticket-impact: both must refuse with exit 1 and touch nothing
WT=/home/namli/www/ticket/.claude/worktrees/tic-6rw0-guarded-start-reopen
ONLY=$(mktemp -d); T=$(mktemp -d)
cp "$WT/plugins/ticket-start" "$WT/plugins/ticket-reopen" "$ONLY/"
cd "$T" || exit 1
mkdir .tickets
printf -- '---\nid: ni-0001\nstatus: open\ndeps: []\nlinks: []\n---\n# Open one\n' > .tickets/ni-0001.md
printf -- '---\nid: ni-0002\nstatus: closed\ndeps: []\nlinks: []\n---\n# Closed one\n' > .tickets/ni-0002.md
PATH="$ONLY:/usr/bin:/bin" "$WT/ticket" start ni-0001; echo "[exit $?]"
PATH="$ONLY:/usr/bin:/bin" "$WT/ticket" reopen ni-0002 -m "x"; echo "[exit $?]"
grep -H '^status' .tickets/*.md
rm -rf "$ONLY" "$T"
```

Run: `bash <scratchpad>/no-impact.sh`
Expected output, exactly:

```
Error: tk start needs the ticket-impact plugin on PATH
Use 'tk super start' to bypass the guard
[exit 1]
Error: tk reopen needs the ticket-impact plugin on PATH
Use 'tk super reopen' to bypass the guard
[exit 1]
.tickets/ni-0001.md:status: open
.tickets/ni-0002.md:status: closed
```

(If `/usr/bin:/bin` on this machine happens to contain a `ticket-impact`, the guards will simply work; say so in the report instead of forcing the branch.)

- [ ] **Step 3: Dogfood on this repository's tickets (read-only outcomes)**

Run each as a separate command; every one of them must leave `git status --short .tickets/` empty:

```bash
PATH="$PWD/plugins:$PATH" ./ticket start tic-x75b
PATH="$PWD/plugins:$PATH" ./ticket start tic-zmz1
PATH="$PWD/plugins:$PATH" ./ticket reopen tic-6rw0 -m "probe"
PATH="$PWD/plugins:$PATH" ./ticket help
git status --short .tickets/
```

Expected: `tic-x75b` refused with its open blockers listed (it depends on the guard tickets, `tic-6rw0` among them); `tic-zmz1` refused as closed with the `tk reopen ... --in-progress` hint; `tic-6rw0 is not closed (status: in_progress) - nothing to reopen`; `help` lists `start` and `reopen` with their descriptions under the plugins heading; `git status` prints nothing.

- [ ] **Step 4: Final full run**

Run: `make test 2>&1 | tail -4`
Expected: `17 features passed, 0 failed`, `257 scenarios passed, 0 failed, 0 skipped`

- [ ] **Step 5: Report and STOP**

Load the `managing-tk-tickets` skill. Report to the user, with the actual outputs of Steps 1-4: the test counts, the busybox result, the missing-impact output, what was NOT executed (gawk-specific run, BSD awk, bash 3.2, the real Homebrew/AUR publish), and each acceptance criterion of `tic-6rw0` with its evidence (run `./ticket show tic-6rw0` and go through the list). State what closing `tic-6rw0` would change: run `PATH="$PWD/plugins:$PATH" ./ticket impact tic-6rw0` and quote it (`tic-x75b` stays blocked while `tic-mwhy` / `tic-yxrw` are open; `tic-sa3b` is the parent). Then STOP and ask whether to close `tic-6rw0`. Only on an explicit yes: `./ticket add-note tic-6rw0 "Closed: done - <what was delivered>"`, `./ticket super close tic-6rw0` (on this branch `tk close` is still the unguarded built-in; after `tic-yxrw` merges use `tk close --reason done -m ...`), stage `.tickets/` LAST, commit `chore: close tic-6rw0`. Then offer push and PR (`superpowers:finishing-a-development-branch`); remind that `tic-mwhy` and `tic-yxrw` touch the same doc spots, publish scripts and `features/ticket_status.feature`, so the later merge resolves textual conflicts.

## Post-review amendments

The final whole-branch review found two Important ID-handling issues, fixed identically in both plugin files. `resolve_id` now reads the `id:` line from the front matter only (an awk state machine tracks entry and exit of the `---` block, ignoring any `id:`-looking line in the body) and requires it to round-trip: `tk super show` on that ID must reproduce the exact output already captured, since core resolves by file name and a mismatched `id:` field would otherwise send the write to another ticket. A failed check prints `Error: cannot resolve '<id>': its id: field is missing or does not match the file name (run 'tk lint')` and returns 1. Both plugins also now reject a whitespace-only `<id>` as a usage error (exit 2) directly after the "exactly one `<id>`" check, closing the case where an unset `$ID` variable let core's glob match every ticket in a one-ticket repo. Test coverage grew by 3 scenarios in `ticket_start_guard.feature` and 4 in `ticket_reopen_guard.feature`, bringing the suite to 264 scenarios. The design spec (`docs/superpowers/specs/2026-09-17-ticket-start-reopen-guard-design.md`) carries the current `resolve_id` text and exit-code table.
