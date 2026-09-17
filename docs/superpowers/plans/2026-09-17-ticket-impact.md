# ticket-impact Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the read-only plugin `plugins/ticket-impact` (`tk impact [--porcelain] <id>`) that shows what closing a ticket would change in the dependency graph.

**Architecture:** One standalone bash file. Bash parses the arguments and resolves the (partial) ID to a file; a single awk pass over `"$TICKETS_DIR"/*.md` loads `id`, `status`, `deps`, `parent` and the title of every ticket, computes every fact as if the target were closed, and prints either the human report or the `--porcelain` fact lines. The core `ticket` script is not touched.

**Tech Stack:** bash, POSIX awk (the system awk here is mawk; the code also runs under busybox awk), `find`, `grep`. Tests: Behave (`make test`, needs `uv`).

**Spec:** `docs/superpowers/specs/2026-09-17-ticket-impact-design.md` - read it first; this plan implements it section by section.

## Global Constraints

- Ticket: `tic-5lpp` (already `in_progress`). Branch: `tic-5lpp-ticket-impact` (already checked out). Do not switch branches.
- No changes to the core `ticket` script. No writes to any ticket file from the plugin.
- POSIX awk only: no `asort`, no `gensub`, no `length(array)`; bracket expressions are written `[][ \t]` (never `[\[\] ]`, see `tic-xj6g`). awk is run with `LC_ALL=C` so sorting is byte-wise.
- bash 3.2 compatible: no `mapfile`, no associative arrays, no `${var,,}`.
- Plugin metadata in the first 10 lines, exactly: `# tk-plugin: Show what closing a ticket would change` and `# tk-plugin-version: 1.0.0`.
- Exit codes: 0 impact printed (also "no impact"); 1 ticket not found / ambiguous ID; 2 usage error or no tickets directory.
- Error wording is fixed: `Error: ticket '<id>' not found`, `Error: ambiguous ID '<id>' matches multiple tickets`, `Error: only one ticket ID is accepted`, `Unknown option: <flag>`.
- Porcelain kinds and order are fixed: `status`, `blocker`, `child`, `ready`, `blocked`, `last-child`; lines of one kind sorted by ID.
- NOT added to `pkg/extras.txt` (new plugin, not a core extraction). Packaging scripts discover `plugins/ticket-*` on their own; nothing to change there.
- Tests use existing Behave steps only; do not add step definitions.
- Commit messages: no attribution trailers of any kind (no `Co-Authored-By`, no "Generated with"). The message ends with its last line of real content.
- Before every `git commit` in this repo, follow the `managing-tk-tickets` skill. Tasks 1-3 do not complete `tic-5lpp`, so they do not close it. Task 4 handles the close and must ask the user first.

## File Structure

| File | Responsibility |
|---|---|
| `plugins/ticket-impact` (create, executable) | The whole plugin: argument parsing, ID resolution, awk graph pass, both output modes. |
| `features/ticket_impact.feature` (create) | All Behave scenarios, in three sections: CLI, graph facts (human output), porcelain. |
| `plugins/README.md` (modify) | New `## ticket-impact` section after the `## ticket-lint` section: usage, example, porcelain contract. |
| `README.md` (modify) | One sentence next to the `ticket-lint` mention in the Plugins section. |
| `CHANGELOG.md` (modify) | One line under `## [Unreleased]` -> `### Plugins`. |

How the tests find the plugin: `features/environment.py` puts the repo's `plugins/` directory on `PATH`, and the step `I run "ticket impact ..."` runs the repo's `./ticket`, which dispatches `impact` to `ticket-impact` on `PATH`. The file must be executable or the dispatch silently falls through to "Unknown command".

Run one feature file with: `uv run --with behave behave features/ticket_impact.feature`. Run everything with: `make test`.

---

### Task 1: Plugin skeleton - arguments, ID resolution, header line

**Files:**
- Create: `plugins/ticket-impact`
- Create: `features/ticket_impact.feature`

**Interfaces:**
- Consumes: environment variable `TICKETS_DIR` (exported by the `ticket` dispatcher).
- Produces: executable `plugins/ticket-impact` whose awk program has the loading rules and the functions `trim(s)` and `store()`, the arrays `status[id]`, `deps_of[id]` (comma-separated, no spaces or brackets), `parent_of[id]`, `title_of[id]`, and the awk variables `target` and `porcelain`. Task 2 replaces the `END` block and adds functions; Task 3 adds the porcelain branch.

- [ ] **Step 1: Write the failing scenarios**

Create `features/ticket_impact.feature` with exactly this content:

```gherkin
Feature: Ticket Impact
  As a user or an agent
  I want to see what closing a ticket would change
  So that I never close a ticket without knowing its effect on the graph

  Background:
    Given a clean tickets directory

  # --- CLI: arguments, ID resolution, exit codes ---

  Scenario: Ticket with no relations has no impact
    Given a ticket exists with ID "imp-0001" and title "Lonely"
    When I run "ticket impact imp-0001"
    Then the exit code should be 0
    And the output line 1 should contain "imp-0001 [open] Lonely"
    And the output should contain "No impact: nothing depends on imp-0001"
    And the error output should be empty

  Scenario: Partial ID works
    Given a ticket exists with ID "imp-0001" and title "Lonely"
    When I run "ticket impact 0001"
    Then the exit code should be 0
    And the output line 1 should contain "imp-0001 [open] Lonely"

  Scenario: Ambiguous partial ID fails
    Given a ticket exists with ID "imp-0001" and title "First"
    And a ticket exists with ID "imp-0002" and title "Second"
    When I run "ticket impact imp-"
    Then the exit code should be 1
    And the error output should contain "ambiguous ID 'imp-' matches multiple tickets"
    And the output should be empty

  Scenario: Unknown ID fails
    Given a ticket exists with ID "imp-0001" and title "First"
    When I run "ticket impact nope"
    Then the exit code should be 1
    And the error output should contain "ticket 'nope' not found"

  Scenario: Missing ID prints usage
    When I run "ticket impact"
    Then the exit code should be 2
    And the error output should contain "Usage: tk impact [--porcelain] <id>"

  Scenario: Two IDs are rejected
    Given a ticket exists with ID "imp-0001" and title "First"
    And a ticket exists with ID "imp-0002" and title "Second"
    When I run "ticket impact imp-0001 imp-0002"
    Then the exit code should be 2
    And the error output should contain "only one ticket ID is accepted"

  Scenario: Unknown flag is rejected
    When I run "ticket impact --bogus imp-0001"
    Then the exit code should be 2
    And the error output should contain "Unknown option: --bogus"

  Scenario: No tickets directory is an environment error
    Given the tickets directory does not exist
    When I run "ticket impact imp-0001"
    Then the exit code should be 2
    And the error output should contain "no .tickets directory found"

  Scenario: Help prints usage
    When I run "ticket impact --help"
    Then the exit code should be 0
    And the output should contain "Usage: tk impact [--porcelain] <id>"

  Scenario: tk help lists the plugin
    When I run "ticket help"
    Then the command should succeed
    And the output should match pattern "impact\s+Show what closing a ticket would change"
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run --with behave behave features/ticket_impact.feature 2>&1 | tail -15`
Expected: all 10 scenarios fail (`0 scenarios passed, 10 failed`); the exit-code steps report 1 instead of the expected value because `./ticket` answers "Unknown command: impact".

- [ ] **Step 3: Write the plugin skeleton**

Create `plugins/ticket-impact` with exactly this content:

```bash
#!/usr/bin/env bash
# tk-plugin: Show what closing a ticket would change
# tk-plugin-version: 1.0.0
set -euo pipefail

usage() {
    echo "Usage: tk impact [--porcelain] <id>"
    echo "  --porcelain  stable machine-readable output, one fact per line"
}

porcelain=0
id=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --porcelain) porcelain=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [[ -n "$id" ]]; then
                echo "Error: only one ticket ID is accepted" >&2
                usage >&2
                exit 2
            fi
            id="$1"; shift ;;
    esac
done

# Trim whitespace around the ID (agents sometimes pass " id ")
read -r id <<< "$id" || true
if [[ -z "$id" ]]; then
    usage >&2
    exit 2
fi

if [[ -z "${TICKETS_DIR:-}" || ! -d "$TICKETS_DIR" ]]; then
    echo "Error: no .tickets directory found (searched parent directories)" >&2
    exit 2
fi

# Resolve ticket file (exact or partial match), same rules as ticket-edit
file="$TICKETS_DIR/${id}.md"
if [[ ! -f "$file" ]]; then
    matches=$(find "$TICKETS_DIR" -maxdepth 1 -name "*${id}*.md" 2>/dev/null)
    count=$(printf '%s\n' "$matches" | grep -c . || true)
    if [[ "$count" -eq 1 ]]; then
        file="$matches"
    elif [[ "$count" -gt 1 ]]; then
        echo "Error: ambiguous ID '$id' matches multiple tickets" >&2
        exit 1
    else
        echo "Error: ticket '$id' not found" >&2
        exit 1
    fi
fi
target=$(basename "$file" .md)

LC_ALL=C awk -v target="$target" -v porcelain="$porcelain" '
# --- Loading: one pass over all ticket files ---
FNR == 1 {
    if (seen) store()
    seen = 1
    id = ""; st = ""; deps = ""; parent = ""; title = ""
    # fm: 1 = inside front matter, 2 = body (or the file has no front matter)
    fm = ($0 == "---") ? 1 : 2
    next
}
fm == 1 && /^---$/ { fm = 2; next }
fm == 1 && /^id:/ { id = trim(substr($0, 4)) }
fm == 1 && /^status:/ { st = trim(substr($0, 8)) }
fm == 1 && /^deps:/ { deps = substr($0, 6); gsub(/[][ \t]/, "", deps) }
fm == 1 && /^parent:/ { parent = trim(substr($0, 8)) }
fm == 2 && title == "" && /^# / { title = substr($0, 3) }

function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

function store() {
    if (id == "") return
    status[id] = st
    deps_of[id] = deps
    parent_of[id] = parent
    title_of[id] = title
}

END {
    if (seen) store()
    if (!(target in status)) {
        print "Error: no ticket with id " target " (file name and id field differ?)" > "/dev/stderr"
        exit 1
    }
    printf "%s [%s] %s\n", target, status[target], title_of[target]
    print ""
    print "No impact: nothing depends on " target
}
' "$TICKETS_DIR"/*.md
```

Notes for the implementer:
- `fm` is a small state machine (1 = front matter, 2 = body) instead of toggling on every `---`, so a `---` rule inside the ticket body cannot re-open the front matter.
- `count=$(... | grep -c . || true)`: `grep -c` exits 1 when it counts 0; `|| true` keeps `set -e` from killing the script, and the printed `0` is still captured.
- At this stage the `END` block always prints the "No impact" line; Task 2 replaces it.

- [ ] **Step 4: Make it executable**

Run: `chmod +x plugins/ticket-impact && ls -l plugins/ticket-impact`
Expected: mode starts with `-rwxr-xr-x` or `-rwxrwxr-x`.

- [ ] **Step 5: Run to verify it passes**

Run: `uv run --with behave behave features/ticket_impact.feature 2>&1 | tail -5`
Expected: `10 scenarios passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/ticket-impact features/ticket_impact.feature
git commit -m "feat: ticket-impact plugin skeleton (tic-5lpp)"
```

---

### Task 2: Graph facts and the human report

**Files:**
- Modify: `plugins/ticket-impact` (whole file replaced, the bash part is unchanged)
- Modify: `features/ticket_impact.feature` (append a section)

**Interfaces:**
- Consumes: from Task 1 - the loading rules, `trim`, `store`, arrays `status`, `deps_of`, `parent_of`, `title_of`, variables `target`, `porcelain`.
- Produces: awk functions `is_open(t)`, `add(list, item)`, `sorted(list)`, `other_open_deps(t)`, `depends_on_target(t)`, `entry(t)`, `section(heading, list)`; and in `END`, before any printing, the computed values `blockers`, `children`, `ready`, `blocked` (sorted comma-separated ID lists), `blocked_by[id]` (sorted comma-separated list) and `last_child` (parent ID or `""`). Task 3 prints these in porcelain form.

Rules being implemented (from the spec, every fact is computed as if the target were closed):
- blocker: ID in the target's deps that is not closed; a dangling ID counts; the target itself never counts.
- child: non-closed ticket with `parent == target`.
- ready: non-closed ticket whose deps contain the target and whose other deps are all closed.
- blocked: same, but at least one other dep is not closed; carries those deps.
- last-child: target has a parent that exists and is not closed, and no other non-closed ticket has the same parent.

- [ ] **Step 1: Append the failing scenarios**

Append this block to the end of `features/ticket_impact.feature` (keep one empty line between the last existing scenario and the comment line):

```gherkin
  # --- Graph facts, human output ---

  Scenario: Dependent with a single blocker becomes ready
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Waiting"
    And ticket "imp-0002" depends on "imp-0001"
    When I run "ticket impact imp-0001"
    Then the exit code should be 0
    And the output should contain "Becomes ready:"
    And the output should contain "- imp-0002 [open] Waiting"
    And the output should not contain "Still blocked by others:"
    And the output should not contain "No impact"

  Scenario: Dependent with a second open blocker stays blocked
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Waiting"
    And a ticket exists with ID "imp-0003" and title "Other blocker"
    And ticket "imp-0002" depends on "imp-0001"
    And ticket "imp-0002" depends on "imp-0003"
    When I run "ticket impact imp-0001"
    Then the exit code should be 0
    And the output should contain "Still blocked by others:"
    And the output should contain "- imp-0002 [open] Waiting <- imp-0003"
    And the output should not contain "Becomes ready:"

  Scenario: Dependent whose other blocker is closed becomes ready
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Waiting"
    And a ticket exists with ID "imp-0003" and title "Other blocker"
    And ticket "imp-0002" depends on "imp-0001"
    And ticket "imp-0002" depends on "imp-0003"
    And ticket "imp-0003" has status "closed"
    When I run "ticket impact imp-0001"
    Then the output should contain "Becomes ready:"
    And the output should contain "- imp-0002 [open] Waiting"
    And the output should not contain "Still blocked by others:"

  Scenario: Closed dependents are ignored
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Finished"
    And ticket "imp-0002" depends on "imp-0001"
    And ticket "imp-0002" has status "closed"
    When I run "ticket impact imp-0001"
    Then the exit code should be 0
    And the output should contain "No impact: nothing depends on imp-0001"
    And the output should not contain "imp-0002"

  Scenario: Open children are listed and closed children are not
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Open child" with parent "imp-0001"
    And a ticket exists with ID "imp-0003" and title "Closed child" with parent "imp-0001"
    And ticket "imp-0003" has status "closed"
    When I run "ticket impact imp-0001"
    Then the output should contain "Open children:"
    And the output should contain "- imp-0002 [open] Open child"
    And the output should not contain "imp-0003"

  Scenario: Last open child of an open parent is reported
    Given a ticket exists with ID "imp-par" and title "Epic"
    And a ticket exists with ID "imp-0001" and title "Target" with parent "imp-par"
    And a ticket exists with ID "imp-0002" and title "Done sibling" with parent "imp-par"
    And ticket "imp-0002" has status "closed"
    When I run "ticket impact imp-0001"
    Then the output should contain "Last open child of imp-par [open] Epic - consider closing the parent"

  Scenario: Not the last child while a sibling is open
    Given a ticket exists with ID "imp-par" and title "Epic"
    And a ticket exists with ID "imp-0001" and title "Target" with parent "imp-par"
    And a ticket exists with ID "imp-0002" and title "Open sibling" with parent "imp-par"
    When I run "ticket impact imp-0001"
    Then the output should not contain "Last open child"
    And the output should contain "No impact: nothing depends on imp-0001"

  Scenario: No last-child hint when the parent is closed
    Given a ticket exists with ID "imp-par" and title "Epic"
    And ticket "imp-par" has status "closed"
    And a ticket exists with ID "imp-0001" and title "Target" with parent "imp-par"
    When I run "ticket impact imp-0001"
    Then the output should not contain "Last open child"

  Scenario: Open blockers of the target are listed
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Blocker"
    And a ticket exists with ID "imp-0003" and title "Resolved blocker"
    And ticket "imp-0003" has status "closed"
    And ticket "imp-0001" depends on "imp-0002"
    And ticket "imp-0001" depends on "imp-0003"
    When I run "ticket impact imp-0001"
    Then the output should contain "Open blockers:"
    And the output should contain "- imp-0002 [open] Blocker"
    And the output should not contain "imp-0003"

  Scenario: A dangling blocker is shown as missing
    Given a ticket exists with ID "imp-0001" and title "Target"
    And ticket "imp-0001" depends on "imp-gone"
    When I run "ticket impact imp-0001"
    Then the output should contain "Open blockers:"
    And the output should contain "- imp-gone [missing]"

  Scenario: A self-dependency is not a blocker
    Given a ticket exists with ID "imp-0001" and title "Target"
    And ticket "imp-0001" depends on "imp-0001"
    When I run "ticket impact imp-0001"
    Then the output should contain "No impact: nothing depends on imp-0001"

  Scenario: Closed target says what a reopen would re-block
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Waiting"
    And ticket "imp-0002" depends on "imp-0001"
    And ticket "imp-0001" has status "closed"
    When I run "ticket impact imp-0001"
    Then the exit code should be 0
    And the output line 1 should contain "imp-0001 [closed] Target"
    And the output should contain "Already closed. Reopening would re-block:"
    And the output should contain "- imp-0002 [open] Waiting"
    And the output should not contain "Becomes ready:"
```

- [ ] **Step 2: Run to verify the new scenarios fail**

Run: `uv run --with behave behave features/ticket_impact.feature 2>&1 | sed -n '/^Failing scenarios/,$p'`
Expected: `14 scenarios passed, 8 failed`. The 8 failing scenarios are:

```
Dependent with a single blocker becomes ready
Dependent with a second open blocker stays blocked
Dependent whose other blocker is closed becomes ready
Open children are listed and closed children are not
Last open child of an open parent is reported
Open blockers of the target are listed
A dangling blocker is shown as missing
Closed target says what a reopen would re-block
```

Four new scenarios already pass because the skeleton always prints "No impact" (`Closed dependents are ignored`, `Not the last child while a sibling is open`, `No last-child hint when the parent is closed`, `A self-dependency is not a blocker`). They are regression guards: they must still pass after Step 3.

- [ ] **Step 3: Implement the graph pass and the human report**

Replace the whole content of `plugins/ticket-impact` with:

```bash
#!/usr/bin/env bash
# tk-plugin: Show what closing a ticket would change
# tk-plugin-version: 1.0.0
set -euo pipefail

usage() {
    echo "Usage: tk impact [--porcelain] <id>"
    echo "  --porcelain  stable machine-readable output, one fact per line"
}

porcelain=0
id=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --porcelain) porcelain=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [[ -n "$id" ]]; then
                echo "Error: only one ticket ID is accepted" >&2
                usage >&2
                exit 2
            fi
            id="$1"; shift ;;
    esac
done

# Trim whitespace around the ID (agents sometimes pass " id ")
read -r id <<< "$id" || true
if [[ -z "$id" ]]; then
    usage >&2
    exit 2
fi

if [[ -z "${TICKETS_DIR:-}" || ! -d "$TICKETS_DIR" ]]; then
    echo "Error: no .tickets directory found (searched parent directories)" >&2
    exit 2
fi

# Resolve ticket file (exact or partial match), same rules as ticket-edit
file="$TICKETS_DIR/${id}.md"
if [[ ! -f "$file" ]]; then
    matches=$(find "$TICKETS_DIR" -maxdepth 1 -name "*${id}*.md" 2>/dev/null)
    count=$(printf '%s\n' "$matches" | grep -c . || true)
    if [[ "$count" -eq 1 ]]; then
        file="$matches"
    elif [[ "$count" -gt 1 ]]; then
        echo "Error: ambiguous ID '$id' matches multiple tickets" >&2
        exit 1
    else
        echo "Error: ticket '$id' not found" >&2
        exit 1
    fi
fi
target=$(basename "$file" .md)

LC_ALL=C awk -v target="$target" -v porcelain="$porcelain" '
# --- Loading: one pass over all ticket files ---
FNR == 1 {
    if (seen) store()
    seen = 1
    id = ""; st = ""; deps = ""; parent = ""; title = ""
    # fm: 1 = inside front matter, 2 = body (or the file has no front matter)
    fm = ($0 == "---") ? 1 : 2
    next
}
fm == 1 && /^---$/ { fm = 2; next }
fm == 1 && /^id:/ { id = trim(substr($0, 4)) }
fm == 1 && /^status:/ { st = trim(substr($0, 8)) }
fm == 1 && /^deps:/ { deps = substr($0, 6); gsub(/[][ \t]/, "", deps) }
fm == 1 && /^parent:/ { parent = trim(substr($0, 8)) }
fm == 2 && title == "" && /^# / { title = substr($0, 3) }

function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

function store() {
    if (id == "") return
    status[id] = st
    deps_of[id] = deps
    parent_of[id] = parent
    title_of[id] = title
}

# A dangling ID counts as open, as in cmd_ready. The "in" test keeps awk from
# creating an empty status[] entry for it.
function is_open(t) { return !(t in status) || status[t] != "closed" }

function add(list, item) { return (list == "") ? item : list "," item }

# Comma-separated list -> sorted, de-duplicated comma-separated list
function sorted(list,    n, arr, i, j, tmp, out) {
    n = split(list, arr, ",")
    for (i = 2; i <= n; i++) {
        tmp = arr[i]
        for (j = i - 1; j >= 1 && (arr[j] "") > (tmp ""); j--) arr[j + 1] = arr[j]
        arr[j + 1] = tmp
    }
    out = ""
    for (i = 1; i <= n; i++)
        if (arr[i] != "" && (i == 1 || arr[i] != arr[i - 1])) out = add(out, arr[i])
    return out
}

# Open deps of ticket t, the target excluded (it is treated as closed)
function other_open_deps(t,    n, arr, i, out) {
    out = ""
    n = split(deps_of[t], arr, ",")
    for (i = 1; i <= n; i++)
        if (arr[i] != "" && arr[i] != target && is_open(arr[i])) out = add(out, arr[i])
    return sorted(out)
}

function depends_on_target(t,    n, arr, i) {
    n = split(deps_of[t], arr, ",")
    for (i = 1; i <= n; i++) if (arr[i] == target) return 1
    return 0
}

function entry(t) {
    if (t in status) return sprintf("- %s [%s] %s", t, status[t], title_of[t])
    return sprintf("- %s [missing]", t)
}

function section(heading, list,    n, arr, i) {
    if (list == "") return
    print ""
    print heading
    n = split(list, arr, ",")
    for (i = 1; i <= n; i++) print entry(arr[i])
}

END {
    if (seen) store()
    if (!(target in status)) {
        print "Error: no ticket with id " target " (file name and id field differ?)" > "/dev/stderr"
        exit 1
    }

    blockers = other_open_deps(target)

    children = ""; ready = ""; blocked = ""
    parent = parent_of[target]
    open_siblings = 0
    for (t in status) {
        if (t == target || status[t] == "closed") continue
        if (parent_of[t] == target) children = add(children, t)
        if (parent != "" && parent_of[t] == parent) open_siblings++
        if (depends_on_target(t)) {
            by = other_open_deps(t)
            if (by == "") ready = add(ready, t)
            else { blocked = add(blocked, t); blocked_by[t] = by }
        }
    }
    children = sorted(children); ready = sorted(ready); blocked = sorted(blocked)

    last_child = (parent != "" && parent != target && (parent in status) \
        && status[parent] != "closed" && open_siblings == 0) ? parent : ""

    printf "%s [%s] %s\n", target, status[target], title_of[target]
    if (blockers == "" && children == "" && ready == "" && blocked == "" && last_child == "") {
        print ""
        print "No impact: nothing depends on " target
        exit 0
    }
    section("Open blockers:", blockers)
    section("Open children:", children)
    section((status[target] == "closed") ? "Already closed. Reopening would re-block:" : "Becomes ready:", ready)
    if (blocked != "") {
        print ""
        print "Still blocked by others:"
        n = split(blocked, arr, ",")
        for (i = 1; i <= n; i++) {
            by = blocked_by[arr[i]]
            gsub(/,/, ", ", by)
            print entry(arr[i]) " <- " by
        }
    }
    if (last_child != "") {
        print ""
        printf "Last open child of %s [%s] %s - consider closing the parent\n", last_child, status[last_child], title_of[last_child]
    }
}
' "$TICKETS_DIR"/*.md
```

Notes for the implementer:
- `is_open` tests `t in status` first. Reading `status[t]` for an unknown ID would create an empty entry in awk and the dangling ID would later show up in `for (t in status)`.
- `(arr[j] "") > (tmp "")` forces a string comparison; IDs that look like numbers would otherwise be compared numerically.
- `for (t in status)` has no defined order in awk, which is why every list goes through `sorted()` before it is printed.

- [ ] **Step 4: Run to verify it passes**

Run: `uv run --with behave behave features/ticket_impact.feature 2>&1 | tail -5`
Expected: `22 scenarios passed, 0 failed`.

- [ ] **Step 5: Check against this repository's real tickets**

Run: `./ticket impact tic-zmz1`
Expected (tic-zmz1 is closed; titles may be longer than shown):

```
tic-zmz1 [closed] Decide guard style: shadow built-ins, new verbs, or core changes

Already closed. Reopening would re-block:
- tic-6rw0 [open] Add guarded start and reopen plugins
- tic-mwhy [open] Add guarded dep and undep plugins: reject self-deps and cycles, record the reason

Still blocked by others:
- tic-yxrw [open] Add guarded close plugin with resolution reason and unblock report <- tic-5lpp
```

- [ ] **Step 6: Commit**

```bash
git add plugins/ticket-impact features/ticket_impact.feature
git commit -m "feat: ticket-impact graph facts and human report (tic-5lpp)"
```

---

### Task 3: `--porcelain` output

**Files:**
- Modify: `plugins/ticket-impact` (two insertions in the awk program)
- Modify: `features/ticket_impact.feature` (append a section)

**Interfaces:**
- Consumes: from Task 2 - `blockers`, `children`, `ready`, `blocked`, `blocked_by[id]`, `last_child`, all computed in `END` before the first `printf`; the awk variable `porcelain` (0 or 1), already passed with `-v` since Task 1.
- Produces: the stable porcelain contract used later by `ticket-close` (`tic-yxrw`) and `ticket-reopen` (`tic-6rw0`):

```
status <status>
blocker <id>
child <id>
ready <id>
blocked <id> <dep>[,<dep>...]
last-child <parent-id>
```

`status` is always line 1. Kinds appear in this order, a kind without facts prints nothing, lines of one kind are sorted by ID.

- [ ] **Step 1: Append the failing scenarios**

Append this block to the end of `features/ticket_impact.feature`:

```gherkin
  # --- Porcelain ---

  Scenario: Porcelain prints every fact kind in a fixed order
    Given a ticket exists with ID "imp-par" and title "Epic"
    And a ticket exists with ID "imp-0001" and title "Target" with parent "imp-par"
    And a ticket exists with ID "imp-0002" and title "Blocker"
    And a ticket exists with ID "imp-0003" and title "Child" with parent "imp-0001"
    And a ticket exists with ID "imp-0004" and title "Ready one"
    And a ticket exists with ID "imp-0005" and title "Blocked one"
    And a ticket exists with ID "imp-0006" and title "Other blocker"
    And ticket "imp-0001" depends on "imp-0002"
    And ticket "imp-0004" depends on "imp-0001"
    And ticket "imp-0005" depends on "imp-0001"
    And ticket "imp-0005" depends on "imp-0006"
    And ticket "imp-0005" depends on "imp-0002"
    When I run "ticket impact --porcelain imp-0001"
    Then the exit code should be 0
    And the output line 1 should contain "status open"
    And the output line 2 should contain "blocker imp-0002"
    And the output line 3 should contain "child imp-0003"
    And the output line 4 should contain "ready imp-0004"
    And the output line 5 should contain "blocked imp-0005 imp-0002,imp-0006"
    And the output line 6 should contain "last-child imp-par"
    And the output line count should be 6
    And the error output should be empty

  Scenario: Porcelain sorts facts by ID
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0003" and title "Created first"
    And a ticket exists with ID "imp-0002" and title "Created second"
    And ticket "imp-0003" depends on "imp-0001"
    And ticket "imp-0002" depends on "imp-0001"
    When I run "ticket impact --porcelain imp-0001"
    Then the output line 2 should contain "ready imp-0002"
    And the output line 3 should contain "ready imp-0003"
    And the output line count should be 3

  Scenario: Porcelain with no impact prints only the status
    Given a ticket exists with ID "imp-0001" and title "Lonely"
    When I run "ticket impact --porcelain imp-0001"
    Then the exit code should be 0
    And the output should be "status open"

  Scenario: Porcelain flag may follow the ID
    Given a ticket exists with ID "imp-0001" and title "Lonely"
    When I run "ticket impact imp-0001 --porcelain"
    Then the exit code should be 0
    And the output should be "status open"

  Scenario: Porcelain on a closed target keeps the ready lines
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Waiting"
    And ticket "imp-0002" depends on "imp-0001"
    And ticket "imp-0001" has status "closed"
    When I run "ticket impact --porcelain imp-0001"
    Then the output line 1 should contain "status closed"
    And the output line 2 should contain "ready imp-0002"
    And the output line count should be 2
```

- [ ] **Step 2: Run to verify the new scenarios fail**

Run: `uv run --with behave behave features/ticket_impact.feature 2>&1 | sed -n '/^Failing scenarios/,$p'`
Expected: `22 scenarios passed, 5 failed`; all 5 porcelain scenarios fail because the flag is parsed but the output is still the human report.

- [ ] **Step 3: Add the `facts` function**

In `plugins/ticket-impact`, insert this function directly above the line `END {`, after the closing brace of `function section(...)`, with one empty line before and after it:

```awk
function facts(kind, list,    n, arr, i) {
    n = split(list, arr, ",")
    for (i = 1; i <= n; i++) print kind " " arr[i]
}
```

- [ ] **Step 4: Add the porcelain branch**

In the `END` block, insert this branch directly above the line `    printf "%s [%s] %s\n", target, status[target], title_of[target]` (after the `last_child = ...` assignment), followed by one empty line:

```awk
    if (porcelain) {
        print "status " status[target]
        facts("blocker", blockers)
        facts("child", children)
        facts("ready", ready)
        n = split(blocked, arr, ",")
        for (i = 1; i <= n; i++) print "blocked " arr[i] " " blocked_by[arr[i]]
        if (last_child != "") print "last-child " last_child
        exit 0
    }
```

After both insertions the complete file must be identical to this:

```bash
#!/usr/bin/env bash
# tk-plugin: Show what closing a ticket would change
# tk-plugin-version: 1.0.0
set -euo pipefail

usage() {
    echo "Usage: tk impact [--porcelain] <id>"
    echo "  --porcelain  stable machine-readable output, one fact per line"
}

porcelain=0
id=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --porcelain) porcelain=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [[ -n "$id" ]]; then
                echo "Error: only one ticket ID is accepted" >&2
                usage >&2
                exit 2
            fi
            id="$1"; shift ;;
    esac
done

# Trim whitespace around the ID (agents sometimes pass " id ")
read -r id <<< "$id" || true
if [[ -z "$id" ]]; then
    usage >&2
    exit 2
fi

if [[ -z "${TICKETS_DIR:-}" || ! -d "$TICKETS_DIR" ]]; then
    echo "Error: no .tickets directory found (searched parent directories)" >&2
    exit 2
fi

# Resolve ticket file (exact or partial match), same rules as ticket-edit
file="$TICKETS_DIR/${id}.md"
if [[ ! -f "$file" ]]; then
    matches=$(find "$TICKETS_DIR" -maxdepth 1 -name "*${id}*.md" 2>/dev/null)
    count=$(printf '%s\n' "$matches" | grep -c . || true)
    if [[ "$count" -eq 1 ]]; then
        file="$matches"
    elif [[ "$count" -gt 1 ]]; then
        echo "Error: ambiguous ID '$id' matches multiple tickets" >&2
        exit 1
    else
        echo "Error: ticket '$id' not found" >&2
        exit 1
    fi
fi
target=$(basename "$file" .md)

LC_ALL=C awk -v target="$target" -v porcelain="$porcelain" '
# --- Loading: one pass over all ticket files ---
FNR == 1 {
    if (seen) store()
    seen = 1
    id = ""; st = ""; deps = ""; parent = ""; title = ""
    # fm: 1 = inside front matter, 2 = body (or the file has no front matter)
    fm = ($0 == "---") ? 1 : 2
    next
}
fm == 1 && /^---$/ { fm = 2; next }
fm == 1 && /^id:/ { id = trim(substr($0, 4)) }
fm == 1 && /^status:/ { st = trim(substr($0, 8)) }
fm == 1 && /^deps:/ { deps = substr($0, 6); gsub(/[][ \t]/, "", deps) }
fm == 1 && /^parent:/ { parent = trim(substr($0, 8)) }
fm == 2 && title == "" && /^# / { title = substr($0, 3) }

function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

function store() {
    if (id == "") return
    status[id] = st
    deps_of[id] = deps
    parent_of[id] = parent
    title_of[id] = title
}

# A dangling ID counts as open, as in cmd_ready. The "in" test keeps awk from
# creating an empty status[] entry for it.
function is_open(t) { return !(t in status) || status[t] != "closed" }

function add(list, item) { return (list == "") ? item : list "," item }

# Comma-separated list -> sorted, de-duplicated comma-separated list
function sorted(list,    n, arr, i, j, tmp, out) {
    n = split(list, arr, ",")
    for (i = 2; i <= n; i++) {
        tmp = arr[i]
        for (j = i - 1; j >= 1 && (arr[j] "") > (tmp ""); j--) arr[j + 1] = arr[j]
        arr[j + 1] = tmp
    }
    out = ""
    for (i = 1; i <= n; i++)
        if (arr[i] != "" && (i == 1 || arr[i] != arr[i - 1])) out = add(out, arr[i])
    return out
}

# Open deps of ticket t, the target excluded (it is treated as closed)
function other_open_deps(t,    n, arr, i, out) {
    out = ""
    n = split(deps_of[t], arr, ",")
    for (i = 1; i <= n; i++)
        if (arr[i] != "" && arr[i] != target && is_open(arr[i])) out = add(out, arr[i])
    return sorted(out)
}

function depends_on_target(t,    n, arr, i) {
    n = split(deps_of[t], arr, ",")
    for (i = 1; i <= n; i++) if (arr[i] == target) return 1
    return 0
}

function entry(t) {
    if (t in status) return sprintf("- %s [%s] %s", t, status[t], title_of[t])
    return sprintf("- %s [missing]", t)
}

function section(heading, list,    n, arr, i) {
    if (list == "") return
    print ""
    print heading
    n = split(list, arr, ",")
    for (i = 1; i <= n; i++) print entry(arr[i])
}

function facts(kind, list,    n, arr, i) {
    n = split(list, arr, ",")
    for (i = 1; i <= n; i++) print kind " " arr[i]
}

END {
    if (seen) store()
    if (!(target in status)) {
        print "Error: no ticket with id " target " (file name and id field differ?)" > "/dev/stderr"
        exit 1
    }

    blockers = other_open_deps(target)

    children = ""; ready = ""; blocked = ""
    parent = parent_of[target]
    open_siblings = 0
    for (t in status) {
        if (t == target || status[t] == "closed") continue
        if (parent_of[t] == target) children = add(children, t)
        if (parent != "" && parent_of[t] == parent) open_siblings++
        if (depends_on_target(t)) {
            by = other_open_deps(t)
            if (by == "") ready = add(ready, t)
            else { blocked = add(blocked, t); blocked_by[t] = by }
        }
    }
    children = sorted(children); ready = sorted(ready); blocked = sorted(blocked)

    last_child = (parent != "" && parent != target && (parent in status) \
        && status[parent] != "closed" && open_siblings == 0) ? parent : ""

    if (porcelain) {
        print "status " status[target]
        facts("blocker", blockers)
        facts("child", children)
        facts("ready", ready)
        n = split(blocked, arr, ",")
        for (i = 1; i <= n; i++) print "blocked " arr[i] " " blocked_by[arr[i]]
        if (last_child != "") print "last-child " last_child
        exit 0
    }

    printf "%s [%s] %s\n", target, status[target], title_of[target]
    if (blockers == "" && children == "" && ready == "" && blocked == "" && last_child == "") {
        print ""
        print "No impact: nothing depends on " target
        exit 0
    }
    section("Open blockers:", blockers)
    section("Open children:", children)
    section((status[target] == "closed") ? "Already closed. Reopening would re-block:" : "Becomes ready:", ready)
    if (blocked != "") {
        print ""
        print "Still blocked by others:"
        n = split(blocked, arr, ",")
        for (i = 1; i <= n; i++) {
            by = blocked_by[arr[i]]
            gsub(/,/, ", ", by)
            print entry(arr[i]) " <- " by
        }
    }
    if (last_child != "") {
        print ""
        printf "Last open child of %s [%s] %s - consider closing the parent\n", last_child, status[last_child], title_of[last_child]
    }
}
' "$TICKETS_DIR"/*.md
```

- [ ] **Step 5: Run to verify it passes**

Run: `uv run --with behave behave features/ticket_impact.feature 2>&1 | tail -5`
Expected: `27 scenarios passed, 0 failed`.

- [ ] **Step 6: Check against this repository's real tickets**

Run: `./ticket impact --porcelain tic-5lpp`
Expected:

```
status in_progress
ready tic-yxrw
blocked tic-x75b tic-6rw0,tic-mwhy,tic-vezj,tic-xg2z,tic-yxrw
```

- [ ] **Step 7: Commit**

```bash
git add plugins/ticket-impact features/ticket_impact.feature
git commit -m "feat: ticket-impact --porcelain output (tic-5lpp)"
```

---

### Task 4: Documentation, changelog, full test run, ticket close

**Files:**
- Modify: `plugins/README.md` (append a section at the end of the file, after the `ticket-lint` section)
- Modify: `README.md:144` (the paragraph that starts with `**Official plugins** live in`)
- Modify: `CHANGELOG.md` (the `### Plugins` list under `## [Unreleased]`)
- Modify: `.tickets/tic-5lpp.md` (through `tk` only)

**Interfaces:**
- Consumes: the finished plugin from Tasks 1-3.
- Produces: nothing for later tasks.

- [ ] **Step 1: Document the plugin in `plugins/README.md`**

Append to the end of `plugins/README.md` (one empty line before the heading):

````markdown
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

```bash
out=$("$TK_SCRIPT" impact --porcelain "$id") || exit $?
if grep -q '^blocker \|^child ' <<<"$out"; then
    echo "refusing to close $id: open blockers or children" >&2
    exit 1
fi
awk '$1 == "ready" { print $2 }' <<<"$out"   # tickets that become ready
```

Requires only bash, POSIX awk, `find` and `grep`.
````

- [ ] **Step 2: Mention the plugin in `README.md`**

In `README.md`, in the paragraph starting with `**Official plugins** live in`, replace the last sentence

```
It is not part of `ticket-extras`: copy or symlink `plugins/ticket-lint` into your PATH, or install the `ticket-lint` package.
```

with

```
`ticket-impact` (`tk impact <id>`) shows what closing a ticket would change - which dependents become ready, which stay blocked, open blockers and children - and has a `--porcelain` mode for scripts. Neither is part of `ticket-extras`: copy or symlink `plugins/ticket-lint` and `plugins/ticket-impact` into your PATH (or put the `plugins/` directory on your PATH), or install the `ticket-lint` / `ticket-impact` packages.
```

- [ ] **Step 3: Add the changelog line**

In `CHANGELOG.md`, under `## [Unreleased]` -> `### Plugins`, add after the `ticket-lint 1.0.0` line:

```
- ticket-impact 1.0.0: New plugin, `tk impact [--porcelain] <id>` shows what closing a ticket would change (open blockers and children, dependents that become ready or stay blocked, last open child of a parent); `--porcelain` prints one stable fact per line for other plugins
```

- [ ] **Step 4: Run the whole suite**

Run: `make test 2>&1 | tail -6`
Expected: `14 features passed, 0 failed`, `187 scenarios passed, 0 failed` (160 existing + 27 new). Any failure outside `ticket_impact.feature` means something else was touched by mistake - find it with `git status` before going on.

- [ ] **Step 5: Verify the acceptance criteria of `tic-5lpp`**

Run each and compare:

```bash
./ticket help | grep -n 'impact'                 # "impact   Show what closing a ticket would change"
head -3 plugins/ticket-impact                    # shebang, tk-plugin, tk-plugin-version: 1.0.0
grep -c 'impact' pkg/extras.txt                  # 0
./ticket lint; echo "lint exit=$?"               # lint exit=0
```

- [ ] **Step 6: Commit the docs**

```bash
git add plugins/README.md README.md CHANGELOG.md
git commit -m "docs: document ticket-impact plugin (tic-5lpp)"
```

- [ ] **Step 7: Ask before closing `tic-5lpp`**

Do NOT close the ticket on your own. Show the user:
- the evidence from Steps 4 and 5;
- the forecast from the new command itself: `./ticket impact tic-5lpp` (expected: `tic-yxrw` becomes ready, `tic-x75b` stays blocked);
- the one deviation from the ticket text: `--porcelain` instead of `--ids-ready` (already recorded as a note on `tic-5lpp`, `tic-yxrw`, `tic-6rw0`).

Only after an explicit yes:

```bash
./ticket add-note tic-5lpp "Closed: done - plugins/ticket-impact 1.0.0: tk impact [--porcelain] <id>, 27 scenarios in features/ticket_impact.feature"
./ticket close tic-5lpp
./ticket dep cycle
./ticket ready
git add .tickets/
git commit -m "chore: close tic-5lpp (ticket-impact)"
```

Report which tickets appeared in `tk ready` after the close. Pushing and opening a PR are separate requests - do them only when the user asks (use `GH_CONFIG_DIR=$HOME/.config/gh-namli gh ...` for any `gh` call in this repo).
