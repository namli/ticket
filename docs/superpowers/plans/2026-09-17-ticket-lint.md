# ticket-lint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `tk lint` plugin that checks every ticket in `.tickets/` for broken graph invariants (and, on request, skill conventions) and reports them in `file:line: level: message [rule]` format with meaningful exit codes.

**Architecture:** One new executable, `plugins/ticket-lint`: a bash wrapper (flags, environment checks, sorting, exit code) around a single POSIX awk program that loads all tickets in one pass and runs one `check_<group>()` function per rule group in `END`, every finding going through one `emit()` function. The core `ticket` script is not touched.

**Tech Stack:** bash, POSIX awk, `sort`; tests in Behave (Python) run with `make test` (`uv run --with behave behave`).

**Spec:** `docs/superpowers/specs/2026-09-17-ticket-lint-design.md` - read it before starting; this plan implements it rule for rule.

**Ticket:** `tic-5cgv` (already `in_progress`). Branch: `feat/ticket-lint` (already created; the spec and this plan are committed on it).

All code in this plan was prototyped outside the repository and verified: every stage below passes its scenarios under both mawk and busybox awk, and each "run to see it fail" step was observed to fail with the scenario counts quoted.

## Global Constraints

- POSIX awk only: no `gensub`, `asorti`, three-argument `match`, `PROCINFO`. Inside a bracket expression a backslash is a literal character in POSIX, so strip brackets with `/[][]/`, never `/[\[\]]/` (busybox awk breaks on the latter).
- No new runtime dependencies: no `tsort`, `jq`, `yq`, `git`.
- Do not modify the core script `ticket`.
- Do not add `lint` to `pkg/extras.txt` (new plugin, not a core extraction).
- Exit codes: 0 = no errors (warnings allowed unless `--strict`; also an empty tickets directory), 1 = errors (or warnings with `--strict`), 2 = unknown option or no tickets directory.
- Finding format, exactly: `<path>:<line>: <level>: <message> [<rule>]` on stdout, sorted with `LC_ALL=C sort -t: -k1,1 -k2,2n`; summary `N errors, M warnings` on stderr only when there are findings; a clean run prints nothing on either stream.
- A closed ticket gets no findings except `id-mismatch`, `invalid-status` and the opt-in `close-note`.
- Commit messages: conventional prefix, no attribution trailers of any kind (no `Co-Authored-By`, no "Generated with" footer).
- This project tracks work with `tk`. Do not run `tk close` without the user's explicit yes (Task 5 spells out the procedure). `.tickets/` is staged last.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `plugins/ticket-lint` | create, mode 755 | the plugin: wrapper + awk program |
| `features/ticket_lint.feature` | create | one scenario per rule, flags, exit codes, format |
| `features/steps/ticket_steps.py` | append a "Lint Steps" section at the end | fixtures for invalid tickets, exit-code and stderr assertions |
| `plugins/README.md` | append a `## ticket-lint` section | rules, flags, exit codes, hook snippets |
| `README.md` | one paragraph in `## Plugins` | pointer to official non-bundled plugins |
| `CHANGELOG.md` | one line under `[Unreleased]` -> `### Plugins` | release note |

Test harness facts you need: `features/environment.py` prepends `plugins/` to `PATH`, so `ticket lint` in a scenario resolves to `plugins/ticket-lint`. Every scenario runs in a fresh temp directory; the step `a ticket exists with ID "X" and title "T"` writes `.tickets/X.md` with this exact layout, which is why the scenarios assert these line numbers: line 1 `---`, 2 `id`, 3 `status`, 4 `deps`, 5 `links`, 6 `created`, 7 `type`, 8 `priority`, 9 `parent` (only with the `with parent` variant), then `---`. The step `the output should be "..."` compares stdout only; `the output should contain "..."` searches stdout + stderr. Step texts may not contain a double quote, so scenarios assert rule ids and quote-free message parts.

Run one feature with: `uv run --with behave behave features/ticket_lint.feature`. Run everything with: `make test`.

---

### Task 1: Plugin skeleton, loader, id and field rules

**Files:**
- Modify: `features/steps/ticket_steps.py` (append at end of file)
- Create: `features/ticket_lint.feature`
- Create: `plugins/ticket-lint`

**Interfaces:**
- Consumes: nothing.
- Produces (awk, used by every later task): arrays `files[1..nfiles]` (ticket ids in file order), `exists[id]`, `field[id, key]`, `line[id, key]`, `dep[id, 1..ndeps[id]]`, `lnk[id, 1..nlinks[id]]`, `haslink[id, other]`; functions `emit(id, ln, level, rule, msg)`, `is_closed(id)`, `plural(count, word)`; variables `dir`, `conventions`, `strict` passed with `-v`; the `END` block that later tasks extend. Produces (Behave steps, used by every later task): `ticket "X" has raw field "F" set to "V"`, `ticket "X" has no field "F"`, `ticket "X" has a one-way link to "Y"`, `ticket "X" has a note "TEXT"`, `ticket "X" has body line "TEXT"`, `the exit code should be N`, `the error output should be empty`, `the error output should contain "TEXT"`.

- [ ] **Step 1: Append the lint steps to `features/steps/ticket_steps.py`**

Add this at the very end of the file (all steps for the whole plan are added now, so later tasks only touch the feature file and the plugin):

```python
# ============================================================================
# Lint Steps
# ============================================================================

def _ticket_file(context, ticket_id):
    return Path(context.test_dir) / '.tickets' / f'{ticket_id}.md'


@given(r'ticket "(?P<ticket_id>[^"]+)" has raw field "(?P<field>[^"]+)" set to "(?P<value>[^"]*)"')
def step_ticket_raw_field(context, ticket_id, field, value):
    """Set a front matter field to an arbitrary (possibly invalid) value."""
    ticket_path = _ticket_file(context, ticket_id)
    content = ticket_path.read_text()
    pattern = rf'^{re.escape(field)}:.*$'
    if re.search(pattern, content, re.MULTILINE):
        content = re.sub(pattern, f'{field}: {value}', content, count=1, flags=re.MULTILINE)
    else:
        # Append as the last front matter field (before the closing ---)
        head, sep, rest = content[4:].partition('\n---\n')
        content = '---\n' + head + f'\n{field}: {value}' + sep + rest
    ticket_path.write_text(content)


@given(r'ticket "(?P<ticket_id>[^"]+)" has no field "(?P<field>[^"]+)"')
def step_ticket_no_field(context, ticket_id, field):
    """Remove a front matter field."""
    ticket_path = _ticket_file(context, ticket_id)
    content = ticket_path.read_text()
    content = re.sub(rf'^{re.escape(field)}:.*\n', '', content, count=1, flags=re.MULTILINE)
    ticket_path.write_text(content)


@given(r'ticket "(?P<ticket_id>[^"]+)" has a one-way link to "(?P<link_id>[^"]+)"')
def step_ticket_one_way_link(context, ticket_id, link_id):
    """Add a link on one side only."""
    ticket_path = _ticket_file(context, ticket_id)
    content = ticket_path.read_text()
    content = re.sub(r'^links: \[\]', f'links: [{link_id}]', content, count=1, flags=re.MULTILINE)
    ticket_path.write_text(content)


@given(r'ticket "(?P<ticket_id>[^"]+)" has a note "(?P<text>[^"]+)"')
def step_ticket_has_note(context, ticket_id, text):
    """Append a timestamped note the way tk add-note does."""
    ticket_path = _ticket_file(context, ticket_id)
    content = ticket_path.read_text()
    if '## Notes' not in content:
        content += '\n## Notes\n'
    content += f'\n**2024-01-02T00:00:00Z**\n\n{text}\n'
    ticket_path.write_text(content)


@given(r'ticket "(?P<ticket_id>[^"]+)" has body line "(?P<text>[^"]+)"')
def step_ticket_has_body_line(context, ticket_id, text):
    """Append a raw line to the ticket body."""
    ticket_path = _ticket_file(context, ticket_id)
    ticket_path.write_text(ticket_path.read_text() + f'\n{text}\n')


@then(r'the exit code should be (?P<code>\d+)')
def step_exit_code(context, code):
    assert context.returncode == int(code), \
        f"Expected exit code {code} but got {context.returncode}\nstdout: {context.stdout}\nstderr: {context.stderr}"


@then(r'the error output should be empty')
def step_stderr_empty(context):
    assert context.stderr == '', f"Expected empty stderr but got: {context.stderr}"


@then(r'the error output should contain "(?P<text>[^"]+)"')
def step_stderr_contains(context, text):
    assert text in context.stderr, f"Expected stderr to contain '{text}'\nActual stderr: {context.stderr}"
```

- [ ] **Step 2: Create `features/ticket_lint.feature` with the first section**

```gherkin
Feature: Ticket Lint
  As a user or an agent
  I want to check every ticket for broken invariants in one command
  So that a damaged dependency graph is caught before it is committed

  Background:
    Given a clean tickets directory

  # --- Basics: exit codes and field rules ---

  Scenario: Clean repository prints nothing
    Given a ticket exists with ID "lint-0001" and title "First"
    And a ticket exists with ID "lint-0002" and title "Second"
    And ticket "lint-0002" depends on "lint-0001"
    And ticket "lint-0001" is linked to "lint-0002"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be empty
    And the error output should be empty

  Scenario: Empty tickets directory is clean
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be empty

  Scenario: Unknown option is a usage error
    Given a ticket exists with ID "lint-0001" and title "First"
    When I run "ticket lint --bogus"
    Then the exit code should be 2
    And the error output should contain "Unknown option: --bogus"

  Scenario: No tickets directory is an environment error
    Given the tickets directory does not exist
    When I run "ticket lint"
    Then the exit code should be 2
    And the error output should contain "no .tickets directory found"

  Scenario: A horizontal rule in the body is not front matter
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has body line "---"
    And ticket "lint-0001" has body line "status: bogus"
    And ticket "lint-0001" has body line "---"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be empty

  Scenario: id field differs from the file name
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has raw field "id" set to "other-9999"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should contain ".tickets/lint-0001.md:2: error:"
    And the output should contain "[id-mismatch]"

  Scenario: id field is missing
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has no field "id"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should contain ".tickets/lint-0001.md:1: error: missing id field [id-mismatch]"

  Scenario: Invalid status is reported even on a ticket that is not open
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has raw field "status" set to "done"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should contain ".tickets/lint-0001.md:3: error:"
    And the output should contain "[invalid-status]"

  Scenario: Invalid priority
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has raw field "priority" set to "high"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should contain ".tickets/lint-0001.md:8: error:"
    And the output should contain "[invalid-priority]"

  Scenario: Unknown type is only a warning
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has raw field "type" set to "spike"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should contain ".tickets/lint-0001.md:7: warning:"
    And the output should contain "[invalid-type]"
    And the error output should contain "0 errors, 1 warning"

  Scenario: Strict mode fails on warnings
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has raw field "type" set to "spike"
    When I run "ticket lint --strict"
    Then the exit code should be 1
    And the output should contain "[invalid-type]"
```

- [ ] **Step 3: Run the feature to verify it fails**

Run: `uv run --with behave behave features/ticket_lint.feature`
Expected: FAIL. `ticket lint` is an unknown command, so every scenario that expects exit code 0 or 2 or a finding fails (`Unknown command: lint`, exit code 1). No step may be reported as undefined; if one is, Step 1 was not applied correctly.

- [ ] **Step 4: Create `plugins/ticket-lint`**

```bash
#!/usr/bin/env bash
# tk-plugin: Check tickets for broken graph invariants and convention violations
# tk-plugin-version: 1.0.0
set -euo pipefail

usage() {
    echo "Usage: tk lint [--conventions] [--strict]"
    echo "  --conventions  also check Closed: / Blocked by notes"
    echo "  --strict       exit 1 on warnings too"
}

conventions=0
strict=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --conventions) conventions=1; shift ;;
        --strict) strict=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "${TICKETS_DIR:-}" || ! -d "$TICKETS_DIR" ]]; then
    echo "Error: no .tickets directory found (searched parent directories)" >&2
    exit 2
fi

shopt -s nullglob
files=("$TICKETS_DIR"/*.md)
[[ ${#files[@]} -eq 0 ]] && exit 0

# Show paths relative to the current directory when possible (clickable, CI-friendly)
dir="${TICKETS_DIR%/}"
dir="${dir#"$PWD"/}"

rc=0
out=$(awk -v dir="$dir" -v conventions="$conventions" -v strict="$strict" '
# --- Loading: one pass over all ticket files ---
FNR == 1 {
    n = split(FILENAME, parts, "/")
    cur = parts[n]
    sub(/\.md$/, "", cur)
    files[++nfiles] = cur
    exists[cur] = 1
    # fm: 1 = inside front matter, 2 = body (or the file has no front matter)
    fm = ($0 == "---") ? 1 : 2
    in_notes = 0
    next
}
fm == 1 && /^---$/ { fm = 2; next }
fm == 1 && /^[a-zA-Z][a-zA-Z_-]*:/ {
    key = substr($0, 1, index($0, ":") - 1)
    val = substr($0, index($0, ":") + 1)
    gsub(/^[ \t]+|[ \t]+$/, "", val)
    field[cur, key] = val
    line[cur, key] = FNR
    if (key == "deps" || key == "links") {
        gsub(/[][]/, "", val); gsub(/[ \t]/, "", val)
        cnt = split(val, items, ",")
        for (i = 1; i <= cnt; i++) if (items[i] != "") {
            if (key == "deps") dep[cur, ++ndeps[cur]] = items[i]
            else { lnk[cur, ++nlinks[cur]] = items[i]; haslink[cur, items[i]] = 1 }
        }
    }
    next
}

# --- Reporting ---
function emit(id, ln, level, rule, msg) {
    if (ln == "" || ln == 0) ln = 1
    printf "%s/%s.md:%d: %s: %s [%s]\n", dir, id, ln, level, msg, rule
    if (level == "error") errors++; else warnings++
}
function plural(count, word) { return count " " word (count == 1 ? "" : "s") }
function is_closed(id) { return field[id, "status"] == "closed" }

# --- Rules ---
function check_ids(    f, id) {
    for (f = 1; f <= nfiles; f++) {
        id = files[f]
        if (!((id, "id") in field))
            emit(id, 1, "error", "id-mismatch", "missing id field")
        else if (field[id, "id"] != id)
            emit(id, line[id, "id"], "error", "id-mismatch", "id \"" field[id, "id"] "\" does not match file name \"" id "\"")
    }
}
function check_fields(    f, id, v) {
    for (f = 1; f <= nfiles; f++) {
        id = files[f]
        v = field[id, "status"]
        if (v != "open" && v != "in_progress" && v != "closed")
            emit(id, line[id, "status"], "error", "invalid-status", "invalid status \"" v "\" (open|in_progress|closed)")
        if (is_closed(id)) continue
        v = field[id, "priority"]
        if (v !~ /^[0-4]$/)
            emit(id, line[id, "priority"], "error", "invalid-priority", "invalid priority \"" v "\" (0-4)")
        v = field[id, "type"]
        if (v != "bug" && v != "feature" && v != "task" && v != "epic" && v != "chore")
            emit(id, line[id, "type"], "warning", "invalid-type", "unknown type \"" v "\" (bug|feature|task|epic|chore)")
    }
}

END {
    check_ids()
    check_fields()
    if (errors + warnings > 0)
        print plural(errors + 0, "error") ", " plural(warnings + 0, "warning") | "cat 1>&2"
    exit (errors > 0 || (strict && warnings > 0)) ? 1 : 0
}
' "${files[@]}") || rc=$?

if [[ -n "$out" ]]; then
    printf '%s\n' "$out" | LC_ALL=C sort -t: -k1,1 -k2,2n
fi
exit "$rc"
```

Notes on the non-obvious parts:
- `out=$(awk ...) || rc=$?`: the script runs under `set -euo pipefail`, so awk's exit status 1 must be captured, not allowed to abort the script before the findings are printed.
- The summary goes through `| "cat 1>&2"`, the portable way to write to stderr from awk.
- `fm` is set from line 1 only: a `---` later in the body never re-enters front matter (unlike the toggling parsers in the core script).

- [ ] **Step 5: Make it executable**

Run: `chmod +x plugins/ticket-lint`

- [ ] **Step 6: Run the feature to verify it passes**

Run: `uv run --with behave behave features/ticket_lint.feature`
Expected: PASS, `11 scenarios passed, 0 failed`.

- [ ] **Step 7: Run the whole suite**

Run: `make test`
Expected: PASS, 0 failed (the new steps must not make any existing step ambiguous).

- [ ] **Step 8: Commit**

```bash
git add plugins/ticket-lint features/ticket_lint.feature features/steps/ticket_steps.py
git commit -m "feat: add ticket-lint plugin skeleton with id and field rules"
```

---

### Task 2: Dependency rules and output format

**Files:**
- Modify: `features/ticket_lint.feature` (append)
- Modify: `plugins/ticket-lint` (insert functions above `END {`, replace the `END` block)

**Interfaces:**
- Consumes: `files`, `nfiles`, `exists`, `field`, `line`, `dep`, `ndeps`, `emit()`, `is_closed()` from Task 1.
- Produces: `check_deps()`, `check_cycles()` (with helpers `dfs(node, depth)` and `record_cycle(start, depth)`, globals `color[]`, `stack[]`, `cyc[]`, `seen_cycle[]`), `check_state()`.

- [ ] **Step 1: Append the second section to `features/ticket_lint.feature`**

Add a blank line after the last scenario, then:

```gherkin
  # --- Dependency rules and output format ---

  Scenario: Finding line format and summary
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" depends on "lint-0001"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should be ".tickets/lint-0001.md:4: error: depends on itself [self-dep]"
    And the error output should contain "1 error, 0 warnings"

  Scenario: Findings are sorted by file then line
    Given a ticket exists with ID "lint-0002" and title "Second"
    And a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0002" depends on "lint-0002"
    And ticket "lint-0001" has raw field "priority" set to "9"
    And ticket "lint-0001" depends on "lint-0001"
    When I run "ticket lint"
    Then the output line count should be 3
    And the output line 1 should contain ".tickets/lint-0001.md:4:"
    And the output line 2 should contain ".tickets/lint-0001.md:8:"
    And the output line 3 should contain ".tickets/lint-0002.md:4:"

  Scenario: Dependency on a missing ticket
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" depends on "gone-0000"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should be ".tickets/lint-0001.md:4: error: depends on missing ticket gone-0000 [missing-dep]"

  Scenario: Dependency cycle is reported once
    Given a ticket exists with ID "lint-0001" and title "First"
    And a ticket exists with ID "lint-0002" and title "Second"
    And a ticket exists with ID "lint-0003" and title "Third"
    And ticket "lint-0001" depends on "lint-0002"
    And ticket "lint-0002" depends on "lint-0003"
    And ticket "lint-0003" depends on "lint-0001"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should be ".tickets/lint-0001.md:4: error: dependency cycle: lint-0001 -> lint-0002 -> lint-0003 -> lint-0001 [dep-cycle]"

  Scenario: Cycle through a closed ticket is reported on the open member
    Given a ticket exists with ID "lint-0001" and title "First"
    And a ticket exists with ID "lint-0002" and title "Second"
    And ticket "lint-0001" depends on "lint-0002"
    And ticket "lint-0002" depends on "lint-0001"
    And ticket "lint-0001" has status "closed"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should be ".tickets/lint-0002.md:4: error: dependency cycle: lint-0002 -> lint-0001 -> lint-0002 [dep-cycle]"

  Scenario: Cycle of only closed tickets is ignored
    Given a ticket exists with ID "lint-0001" and title "First"
    And a ticket exists with ID "lint-0002" and title "Second"
    And ticket "lint-0001" depends on "lint-0002"
    And ticket "lint-0002" depends on "lint-0001"
    And ticket "lint-0001" has status "closed"
    And ticket "lint-0002" has status "closed"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be empty

  Scenario: In-progress ticket with an open blocker
    Given a ticket exists with ID "lint-0001" and title "First"
    And a ticket exists with ID "lint-0002" and title "Second"
    And ticket "lint-0002" depends on "lint-0001"
    And ticket "lint-0002" has status "in_progress"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be ".tickets/lint-0002.md:3: warning: in_progress but blocked by open lint-0001 [blocked-in-progress]"

  Scenario: In-progress ticket whose blocker is closed is fine
    Given a ticket exists with ID "lint-0001" and title "First"
    And a ticket exists with ID "lint-0002" and title "Second"
    And ticket "lint-0002" depends on "lint-0001"
    And ticket "lint-0002" has status "in_progress"
    And ticket "lint-0001" has status "closed"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be empty
```

- [ ] **Step 2: Run the feature to verify the new scenarios fail**

Run: `uv run --with behave behave features/ticket_lint.feature`
Expected: FAIL with `13 scenarios passed, 6 failed, 0 skipped` - the scenarios that expect a dependency finding fail because no dependency rule exists yet; the two "is fine / ignored" scenarios already pass.

- [ ] **Step 3: Add the dependency rules to `plugins/ticket-lint`**

Insert these functions immediately above the line `END {`:

```awk
function check_deps(    f, id, i, d) {
    for (f = 1; f <= nfiles; f++) {
        id = files[f]
        if (is_closed(id)) continue
        for (i = 1; i <= ndeps[id]; i++) {
            d = dep[id, i]
            if (d == id)
                emit(id, line[id, "deps"], "error", "self-dep", "depends on itself")
            else if (!(d in exists))
                emit(id, line[id, "deps"], "error", "missing-dep", "depends on missing ticket " d)
        }
    }
}
function dfs(node, depth,    i, child) {
    color[node] = 1
    stack[depth] = node
    for (i = 1; i <= ndeps[node]; i++) {
        child = dep[node, i]
        if (child == node || !(child in exists)) continue
        if (color[child] == 1) record_cycle(child, depth)
        else if (color[child] == 0) dfs(child, depth + 1)
    }
    color[node] = 2
}
function record_cycle(start, depth,    s, i, len, minidx, key, best, msg) {
    for (s = depth; s > 0 && stack[s] != start; s--) ;
    len = 0
    for (i = s; i <= depth; i++) cyc[++len] = stack[i]
    # Normalise (rotate to the smallest id) so each cycle is reported once
    minidx = 1
    for (i = 2; i <= len; i++) if ((cyc[i] "") < (cyc[minidx] "")) minidx = i
    key = ""
    for (i = 0; i < len; i++) key = key cyc[(minidx - 1 + i) % len + 1] ","
    if (key in seen_cycle) return
    seen_cycle[key] = 1
    # Report on the non-closed member with the smallest id; all closed = history
    best = 0
    for (i = 1; i <= len; i++)
        if (!is_closed(cyc[i]) && (best == 0 || (cyc[i] "") < (cyc[best] ""))) best = i
    if (best == 0) return
    msg = ""
    for (i = 0; i < len; i++) msg = msg cyc[(best - 1 + i) % len + 1] " -> "
    emit(cyc[best], line[cyc[best], "deps"], "error", "dep-cycle", "dependency cycle: " msg cyc[best])
}
function check_cycles(    f) {
    for (f = 1; f <= nfiles; f++)
        if (color[files[f]] == 0) dfs(files[f], 0)
}
function check_state(    f, id, i, d) {
    for (f = 1; f <= nfiles; f++) {
        id = files[f]
        if (field[id, "status"] != "in_progress") continue
        for (i = 1; i <= ndeps[id]; i++) {
            d = dep[id, i]
            if (d != id && (d in exists) && !is_closed(d))
                emit(id, line[id, "status"], "warning", "blocked-in-progress", "in_progress but blocked by " field[d, "status"] " " d)
        }
    }
}
```

Then replace the whole `END { ... }` block with:

```awk
END {
    check_ids()
    check_fields()
    check_deps()
    check_cycles()
    check_state()
    if (errors + warnings > 0)
        print plural(errors + 0, "error") ", " plural(warnings + 0, "warning") | "cat 1>&2"
    exit (errors > 0 || (strict && warnings > 0)) ? 1 : 0
}
```

How the cycle detection works: a colouring depth-first search over `deps` (0 = unvisited, 1 = on the current stack, 2 = done), started from every ticket in file order so the result is deterministic. Closed tickets stay in the graph. Reaching a node that is on the stack is a back edge: `record_cycle` copies the stack slice into `cyc[]`, builds a key rotated to the smallest id so the same cycle found from another start is ignored, then reports on the non-closed member with the smallest id, printing the path from that member back to itself. A cycle whose members are all closed is dropped. Self-deps and missing targets are skipped in the search because `check_deps` owns them. `(x "") < (y "")` forces string comparison even for ids that look numeric.

- [ ] **Step 4: Run the feature to verify it passes**

Run: `uv run --with behave behave features/ticket_lint.feature`
Expected: PASS, `19 scenarios passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/ticket-lint features/ticket_lint.feature
git commit -m "feat: ticket-lint dependency rules (self-dep, missing-dep, dep-cycle, blocked-in-progress)"
```

---

### Task 3: Link and parent rules

**Files:**
- Modify: `features/ticket_lint.feature` (append)
- Modify: `plugins/ticket-lint` (insert functions above `END {`, replace the `END` block)

**Interfaces:**
- Consumes: `files`, `nfiles`, `exists`, `field`, `line`, `lnk`, `nlinks`, `haslink`, `emit()`, `is_closed()` from Task 1.
- Produces: `check_links()`, `check_parents()`.

- [ ] **Step 1: Append the third section to `features/ticket_lint.feature`**

Add a blank line after the last scenario, then:

```gherkin
  # --- Link and parent rules ---

  Scenario: Link to a missing ticket
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has a one-way link to "gone-0000"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should be ".tickets/lint-0001.md:5: error: links to missing ticket gone-0000 [missing-link]"

  Scenario: Asymmetric link
    Given a ticket exists with ID "lint-0001" and title "First"
    And a ticket exists with ID "lint-0002" and title "Second"
    And ticket "lint-0001" has a one-way link to "lint-0002"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should be ".tickets/lint-0001.md:5: error: links to lint-0002, but lint-0002 does not link back [asymmetric-link]"

  Scenario: Missing parent
    Given a ticket exists with ID "lint-0001" and title "First" with parent "gone-0000"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should be ".tickets/lint-0001.md:9: error: parent gone-0000 does not exist [missing-parent]"

  Scenario: Parent cycle
    Given a ticket exists with ID "lint-0001" and title "First" with parent "lint-0002"
    And a ticket exists with ID "lint-0002" and title "Second" with parent "lint-0001"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output line count should be 2
    And the output line 1 should contain ".tickets/lint-0001.md:9: error: parent chain leads back to this ticket [parent-cycle]"
    And the output line 2 should contain ".tickets/lint-0002.md:9: error: parent chain leads back to this ticket [parent-cycle]"

  Scenario: Open child of a closed parent
    Given a ticket exists with ID "lint-0001" and title "Parent"
    And a ticket exists with ID "lint-0002" and title "Child" with parent "lint-0001"
    And ticket "lint-0001" has status "closed"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be ".tickets/lint-0002.md:9: warning: parent lint-0001 is closed but this ticket is open [open-child-of-closed]"

  Scenario: Closed tickets are history and get no findings
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" depends on "gone-0000"
    And ticket "lint-0001" depends on "lint-0001"
    And ticket "lint-0001" has a one-way link to "gone-0000"
    And ticket "lint-0001" has raw field "priority" set to "high"
    And ticket "lint-0001" has status "closed"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be empty
```

- [ ] **Step 2: Run the feature to verify the new scenarios fail**

Run: `uv run --with behave behave features/ticket_lint.feature`
Expected: FAIL with `20 scenarios passed, 5 failed, 0 skipped`. The last scenario ("Closed tickets are history") is a guard and passes already; it must keep passing after the next step.

- [ ] **Step 3: Add the link and parent rules to `plugins/ticket-lint`**

Insert these functions immediately above the line `END {`:

```awk
function check_links(    f, id, i, l) {
    for (f = 1; f <= nfiles; f++) {
        id = files[f]
        if (is_closed(id)) continue
        for (i = 1; i <= nlinks[id]; i++) {
            l = lnk[id, i]
            if (l == id) continue
            if (!(l in exists))
                emit(id, line[id, "links"], "error", "missing-link", "links to missing ticket " l)
            else if (!((l, id) in haslink))
                emit(id, line[id, "links"], "error", "asymmetric-link", "links to " l ", but " l " does not link back")
        }
    }
}
function check_parents(    f, id, p, steps) {
    for (f = 1; f <= nfiles; f++) {
        id = files[f]
        if (is_closed(id) || !((id, "parent") in field) || field[id, "parent"] == "") continue
        p = field[id, "parent"]
        if (p != id && !(p in exists)) {
            emit(id, line[id, "parent"], "error", "missing-parent", "parent " p " does not exist")
            continue
        }
        if (p != id && is_closed(p))
            emit(id, line[id, "parent"], "warning", "open-child-of-closed", "parent " p " is closed but this ticket is " field[id, "status"])
        for (steps = 0; steps <= nfiles && p != id && (p in exists); steps++) p = field[p, "parent"]
        if (p == id)
            emit(id, line[id, "parent"], "error", "parent-cycle", "parent chain leads back to this ticket")
    }
}
```

Then replace the whole `END { ... }` block with:

```awk
END {
    check_ids()
    check_fields()
    check_deps()
    check_cycles()
    check_state()
    check_links()
    check_parents()
    if (errors + warnings > 0)
        print plural(errors + 0, "error") ", " plural(warnings + 0, "warning") | "cat 1>&2"
    exit (errors > 0 || (strict && warnings > 0)) ? 1 : 0
}
```

Notes: a link whose target is missing yields only `missing-link`, never `asymmetric-link`. In `check_parents` the walk up the `parent` chain is bounded by `nfiles` steps, so a cycle that does not include the starting ticket cannot loop forever; a ticket that is its own parent is the one-step case of `parent-cycle`. `open-child-of-closed` is reported on the child.

- [ ] **Step 4: Run the feature to verify it passes**

Run: `uv run --with behave behave features/ticket_lint.feature`
Expected: PASS, `25 scenarios passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/ticket-lint features/ticket_lint.feature
git commit -m "feat: ticket-lint link and parent rules"
```

---

### Task 4: Convention rules behind `--conventions`

**Files:**
- Modify: `features/ticket_lint.feature` (append)
- Modify: `plugins/ticket-lint` (extend the loader, insert a function above `END {`, replace the `END` block)

**Interfaces:**
- Consumes: everything from Task 1, the `conventions` awk variable (already passed by the wrapper).
- Produces: loader arrays `closed_note[id]`, `blocked_note[id, dep_id]`; function `check_conventions()`.

- [ ] **Step 1: Append the fourth section to `features/ticket_lint.feature`**

Add a blank line after the last scenario, then:

```gherkin
  # --- Convention rules ---

  Scenario: Convention rules are silent by default
    Given a ticket exists with ID "lint-0001" and title "First"
    And a ticket exists with ID "lint-0002" and title "Second"
    And ticket "lint-0002" depends on "lint-0001"
    And ticket "lint-0001" has status "closed"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be empty

  Scenario: Conventions flag reports missing notes
    Given a ticket exists with ID "lint-0001" and title "First"
    And a ticket exists with ID "lint-0002" and title "Second"
    And a ticket exists with ID "lint-0003" and title "Third"
    And ticket "lint-0003" depends on "lint-0002"
    And ticket "lint-0001" has status "closed"
    When I run "ticket lint --conventions"
    Then the exit code should be 0
    And the output line count should be 2
    And the output line 1 should contain ".tickets/lint-0001.md:1: warning:"
    And the output line 1 should contain "[close-note]"
    And the output line 2 should contain ".tickets/lint-0003.md:4: warning:"
    And the output line 2 should contain "[dep-note]"

  Scenario: Convention notes silence the convention rules
    Given a ticket exists with ID "lint-0001" and title "First"
    And a ticket exists with ID "lint-0002" and title "Second"
    And a ticket exists with ID "lint-0003" and title "Third"
    And ticket "lint-0003" depends on "lint-0002"
    And ticket "lint-0003" has a note "Blocked by lint-0002: needs the API first"
    And ticket "lint-0001" has a note "Closed: done - shipped"
    And ticket "lint-0001" has status "closed"
    When I run "ticket lint --conventions --strict"
    Then the exit code should be 0
    And the output should be empty
```

- [ ] **Step 2: Run the feature to verify the new scenario fails**

Run: `uv run --with behave behave features/ticket_lint.feature`
Expected: FAIL with `27 scenarios passed, 1 failed, 0 skipped` - only "Conventions flag reports missing notes" fails (the flag is accepted but no rule runs); the "silent by default" and "notes silence" scenarios pass already and must keep passing.

- [ ] **Step 3: Teach the loader to read notes**

In `plugins/ticket-lint`, directly after the closing `}` of the block that starts with `fm == 1 && /^[a-zA-Z][a-zA-Z_-]*:/ {`, insert:

```awk
fm == 2 && /^## / { in_notes = ($0 ~ /^## Notes[ \t]*$/); next }
fm == 2 && in_notes && /^Closed: / { closed_note[cur] = 1 }
fm == 2 && in_notes && /^Blocked by [^:]+:/ {
    who = substr($0, 12, index($0, ":") - 12)
    blocked_note[cur, who] = 1
}
```

`substr($0, 12, index($0, ":") - 12)` extracts the id between the 11-character prefix `Blocked by ` and the first colon. Only lines inside the `## Notes` section count; any other `## ` heading ends it.

- [ ] **Step 4: Add the convention rules**

Insert this function immediately above the line `END {`:

```awk
function check_conventions(    f, id, i, d) {
    for (f = 1; f <= nfiles; f++) {
        id = files[f]
        if (is_closed(id)) {
            if (!(id in closed_note))
                emit(id, 1, "warning", "close-note", "closed without a \"Closed: <resolution>\" note")
            continue
        }
        for (i = 1; i <= ndeps[id]; i++) {
            d = dep[id, i]
            if (d != id && (d in exists) && !((id, d) in blocked_note))
                emit(id, line[id, "deps"], "warning", "dep-note", "no \"Blocked by " d ": <reason>\" note")
        }
    }
}
```

Then replace the whole `END { ... }` block with:

```awk
END {
    check_ids()
    check_fields()
    check_deps()
    check_cycles()
    check_state()
    check_links()
    check_parents()
    if (conventions) check_conventions()
    if (errors + warnings > 0)
        print plural(errors + 0, "error") ", " plural(warnings + 0, "warning") | "cat 1>&2"
    exit (errors > 0 || (strict && warnings > 0)) ? 1 : 0
}
```

- [ ] **Step 5: Run the feature to verify it passes**

Run: `uv run --with behave behave features/ticket_lint.feature`
Expected: PASS, `28 scenarios passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/ticket-lint features/ticket_lint.feature
git commit -m "feat: ticket-lint convention rules behind --conventions"
```

---

### Task 5: Documentation, changelog, final verification, ticket

**Files:**
- Modify: `plugins/README.md` (append a section at the end)
- Modify: `README.md` (`## Plugins` section)
- Modify: `CHANGELOG.md` (`## [Unreleased]` -> `### Plugins`)

**Interfaces:**
- Consumes: the finished plugin.
- Produces: nothing for other tasks.

- [ ] **Step 1: Append the `ticket-lint` section to `plugins/README.md`**

````markdown

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
````

- [ ] **Step 2: Add a pointer in `README.md`**

In the `## Plugins` section, directly after the line ``Use `tk super <cmd>` to bypass plugins and run the built-in directly.``, add a blank line and:

```markdown
**Official plugins** live in [`plugins/`](plugins/README.md). Besides the bundled ones, `ticket-lint` (`tk lint`) checks the whole ticket graph for broken invariants - self-dependencies, cycles, dangling references, one-sided links - and works as a pre-commit hook. It is not part of `ticket-extras`: copy or symlink `plugins/ticket-lint` into your PATH, or install the `ticket-lint` package.
```

The usage block in README.md stays unchanged: `lint` is not a bundled plugin and `tk help` lists installed plugins dynamically.

- [ ] **Step 3: Add the changelog entry**

In `CHANGELOG.md`, under `## [Unreleased]` -> `### Plugins`, append after the last `- ticket-...` line:

```markdown
- ticket-lint 1.0.0: New plugin, `tk lint [--conventions] [--strict]` checks tickets for broken graph invariants (self-deps, cycles, missing references, asymmetric links, invalid fields) in `file:line: level: message [rule]` format
```

- [ ] **Step 4: Verify the documented behaviour by hand**

Run from the repository root:

```bash
PATH="$PWD/plugins:$PATH" ./ticket lint --conventions; echo "exit=$?"
PATH="$PWD/plugins:$PATH" ./ticket help | grep -n lint
PATH="$PWD/plugins:$PATH" ./ticket lint --bogus; echo "exit=$?"
```

Expected: the first command prints nothing and `exit=0` (this repository's own tickets are clean); the second shows `lint` with the description "Check tickets for broken graph invariants and convention violations"; the third prints `Unknown option: --bogus` plus usage and `exit=2`.

- [ ] **Step 5: Run the whole suite**

Run: `make test`
Expected: PASS, `13 features passed, 0 failed`, `152 scenarios passed, 0 failed`.

- [ ] **Step 6: Ticket `tic-5cgv` - report and ask before closing**

Follow the `managing-tk-tickets` skill (Closing): the close rides in the commit that completes the work, and only after the user's explicit yes. Do NOT close on your own.

1. `tk show tic-5cgv`: confirm no open Blockers and no open Children; check each acceptance criterion against the evidence from Steps 4-5 (scenarios per rule, clean repo exits 0, `--strict`, README / plugins/README / CHANGELOG updated, metadata present, not in `pkg/extras.txt`).
2. Tell the user: the evidence, the resolution (`done`), and what closing unblocks: nothing becomes ready, because `tic-x75b` also waits for `tic-5lpp`, `tic-yxrw`, `tic-6rw0`, `tic-mwhy`, `tic-vezj`, `tic-xg2z`. STOP and wait for the answer.

- [ ] **Step 7: Commit (with the close if the user said yes)**

If the user said yes:

```bash
tk add-note tic-5cgv "Closed: done - plugins/ticket-lint 1.0.0: 15 rules, --conventions and --strict, 28 behave scenarios, docs and changelog"
tk close tic-5cgv
tk ready
git add plugins/README.md README.md CHANGELOG.md
git add .tickets/
git commit -m "docs: document ticket-lint plugin, close tic-5cgv"
```

If the user said no or did not answer: commit only the documentation and report "ready to close":

```bash
git add plugins/README.md README.md CHANGELOG.md
git commit -m "docs: document ticket-lint plugin"
```

- [ ] **Step 8: Hand over**

Report what `tk ready` shows, and ask the user how to integrate the branch: merge `feat/ticket-lint` into `master`, or push it and open a PR with `GH_CONFIG_DIR=$HOME/.config/gh-namli gh pr create`. Do not push or merge without being asked.
