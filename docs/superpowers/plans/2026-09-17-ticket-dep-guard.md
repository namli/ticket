# ticket-dep / ticket-undep Guards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `tk dep` and `tk undep` are shadowed by a plugin that rejects self-dependencies and cycles, requires a reason and records it as a note, and prints whether the ticket is ready or blocked.

**Architecture:** One bash script, `plugins/ticket-dep`, plus the symlink `plugins/ticket-undep -> ticket-dep`; the mode comes from the invoked name. The plugin only reads ticket files; every write goes through `"$TK_SCRIPT" super dep|undep|add-note`. `tk dep tree` / `tk dep cycle` are passed to the built-in unchanged. The cycle check is one awk pass plus a breadth-first walk.

**Tech Stack:** bash, POSIX awk, `find`; tests in Behave (`uv run --with behave behave`), Gherkin features in `features/`, steps in `features/steps/ticket_steps.py`.

**Spec:** `docs/superpowers/specs/2026-09-17-ticket-dep-guard-design.md` - read it first; this plan argues from it.

## Global Constraints

- Ticket: `tic-mwhy`. Work only in the worktree `/home/namli/www/ticket/.claude/worktrees/tic-mwhy-guarded-dep` (branch `worktree-tic-mwhy-guarded-dep`). Never `cd` to, edit, stash in or switch branches of the main checkout `/home/namli/www/ticket`: another agent is working there.
- Run the repo's script as `./ticket`, not `tk`: `tk` on this machine is a symlink into the main checkout.
- The harness refuses compound shell commands it cannot verify stay inside the worktree. Run plain, separate commands; if a multi-step command is refused, put it in a script under the session scratchpad and run `bash <script>`.
- No changes to the core `ticket` script. The plugin never edits a ticket file itself.
- No `--force`. The only bypass is `tk super dep` / `tk super undep`; refusal messages name it.
- Exit codes: `0` done (or dep already present), `1` guard refusal / ticket not found / undep of an absent dep / delegated built-in failed / post-check failed, `2` usage error or no tickets directory.
- Note texts, exact: `Blocked by <dep-id>: <text>` and `No longer blocked by <dep-id>: <text>`.
- awk must be POSIX: bracket expressions as `/[][]/`, never `/[\[\]]/` (`tic-xj6g`); no `nextfile`, no gawk extensions.
- Plugin metadata in the first 10 lines: `# tk-plugin:` and `# tk-plugin-version: 1.0.0`. NOT added to `pkg/extras.txt`.
- Commit messages: no attribution trailers of any kind (`Co-Authored-By`, "Generated with ..."). The message ends with the last line of real content.
- Before every `git commit`: load the `managing-tk-tickets` skill; stage `.tickets/` last. Do NOT close `tic-mwhy` - closing needs the user's explicit yes (Task 6).
- `gh` only as `GH_CONFIG_DIR=$HOME/.config/gh-namli gh ... --repo namli/ticket`.

## File Structure

| File | Responsibility |
|---|---|
| `plugins/ticket-dep` (create) | The guard: argument parsing, ID resolution, self-dep / duplicate / cycle checks, delegation to `super`, note, state line. |
| `plugins/ticket-undep` (create, symlink to `ticket-dep`) | Makes `tk undep` reach the same script. |
| `features/ticket_dep_guard.feature` (create) | All guard scenarios. |
| `features/steps/ticket_steps.py` (modify) | One new step: `ticket "<id>" should not contain "<text>"`. |
| `features/ticket_dependencies.feature`, `features/id_resolution.feature`, `features/ticket_directory.feature` (modify) | Scenarios that test the built-in `dep` / `undep` go through `ticket super`. |
| `README.md`, `plugins/README.md`, `CHANGELOG.md` (modify) | User documentation. |
| `skills/managing-tk-tickets/SKILL.md`, `skills/managing-tk-tickets/editing.md` (modify) | Minimal edits so the skill matches the tool. |

---

### Task 1: Built-in dep/undep scenarios go through `super`

`features/environment.py` puts `plugins/` on `PATH` for the whole suite, so once `plugins/ticket-dep` exists every `ticket dep A B` in a feature file reaches the guard and fails for lack of `--reason`. These eight scenarios test core behaviour, so they call the built-in explicitly. `dep tree` scenarios stay untouched: they become pass-through coverage.

**Files:**
- Modify: `features/ticket_dependencies.feature` (6 `When` lines, scenarios "Add a dependency" to "Add dependency to non-existent ticket")
- Modify: `features/id_resolution.feature` (scenario "ID resolution works with dep command")
- Modify: `features/ticket_directory.feature` (scenario "Dep command works from subdirectory")

**Interfaces:**
- Consumes: nothing.
- Produces: a suite that stays green when `plugins/ticket-dep` appears in Task 2.

- [ ] **Step 1: Edit `features/ticket_dependencies.feature`**

Replace exactly these six lines (each occurs once with this indentation; lines containing `dep tree` must NOT change):

| Old | New |
|---|---|
| `    When I run "ticket dep task-0001 task-0002"` in scenario "Add a dependency" | `    When I run "ticket super dep task-0001 task-0002"` |
| `    When I run "ticket dep task-0001 task-0002"` in scenario "Add dependency is idempotent" | `    When I run "ticket super dep task-0001 task-0002"` |
| `    When I run "ticket undep task-0001 task-0002"` in scenario "Remove a dependency" | `    When I run "ticket super undep task-0001 task-0002"` |
| `    When I run "ticket undep task-0001 task-0002"` in scenario "Remove non-existent dependency" | `    When I run "ticket super undep task-0001 task-0002"` |
| `    When I run "ticket dep task-0001 nonexistent"` | `    When I run "ticket super dep task-0001 nonexistent"` |
| `    When I run "ticket dep nonexistent task-0001"` | `    When I run "ticket super dep nonexistent task-0001"` |

- [ ] **Step 2: Edit the other two files**

`features/id_resolution.feature`: `    When I run "ticket dep aaaa bbbb"` -> `    When I run "ticket super dep aaaa bbbb"`

`features/ticket_directory.feature`: in scenario "Dep command works from subdirectory", `    When I run "ticket dep task-0001 task-0002"` -> `    When I run "ticket super dep task-0001 task-0002"`

- [ ] **Step 3: Verify no unguarded call is left**

Run: `grep -n '"ticket dep \|"ticket undep ' features/*.feature`
Expected: only lines containing `ticket dep tree` (all in `features/ticket_dependencies.feature`).

- [ ] **Step 4: Run the suite**

Run: `make test`
Expected: `14 features passed, 0 failed`, `180 scenarios passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add features/ticket_dependencies.feature features/id_resolution.feature features/ticket_directory.feature
git commit -m "test: run built-in dep/undep scenarios through tk super (tic-mwhy)"
```

---

### Task 2: The plugin - usage, ID resolution, self-dep, reason notes, exact matching, pass-through

**Files:**
- Create: `features/ticket_dep_guard.feature`
- Modify: `features/steps/ticket_steps.py` (append one step at the end of the file)
- Create: `plugins/ticket-dep` (mode 755)
- Create: `plugins/ticket-undep` (symlink)

**Interfaces:**
- Consumes: `TICKETS_DIR`, `TK_SCRIPT` from the core dispatcher; built-ins `super dep`, `super undep`, `super add-note`.
- Produces (shell functions later tasks call): `resolve_id <id>` -> full ID on stdout or return 1; `field_of <full-id> <key>` -> front matter value; `deps_of <full-id>` -> one dep ID per line; `has_dep <full-id> <dep-full-id>` -> exit status; `write_note <full-id> <text>`; globals `mode` (`dep`|`undep`), `id`, `dep_id`, `reason`, `no_note`.

- [ ] **Step 1: Add the missing assertion step**

Append to the end of `features/steps/ticket_steps.py`:

```python


@then(r'ticket "(?P<ticket_id>[^"]+)" should not contain "(?P<text>[^"]+)"')
def step_ticket_not_contains(context, ticket_id, text):
    """Assert ticket file does not contain text."""
    ticket_path = Path(context.test_dir) / '.tickets' / f'{ticket_id}.md'
    content = ticket_path.read_text()
    assert text not in content, f"Ticket should not contain '{text}'\nContent: {content}"
```

- [ ] **Step 2: Write the failing feature**

Create `features/ticket_dep_guard.feature`. The `should have ... in deps` steps are substring checks, so scenarios that care about exactness assert on the whole `deps: [...]` line instead.

```gherkin
Feature: Guarded dep and undep
  As a user or an agent
  I want tk dep and tk undep to refuse broken graphs and record the reason
  So that the dependency graph stays true without manual follow-up steps

  Background:
    Given a clean tickets directory
    And a ticket exists with ID "guard-0001" and title "First"
    And a ticket exists with ID "guard-0002" and title "Second"
    And a ticket exists with ID "guard-0003" and title "Third"

  # --- Self-dependency ---

  Scenario: Self-dependency is rejected
    When I run "ticket dep guard-0001 guard-0001 --reason 'loop'"
    Then the exit code should be 1
    And the error output should contain "guard-0001 cannot depend on itself"
    And the error output should contain "tk super dep"
    And ticket "guard-0001" should contain "deps: []"
    And ticket "guard-0001" should not contain "Blocked by"

  Scenario: Self-dependency through a partial ID is rejected
    When I run "ticket dep guard-0001 0001 --reason 'loop'"
    Then the exit code should be 1
    And the error output should contain "guard-0001 cannot depend on itself"

  # --- Notes ---

  Scenario: dep writes the Blocked by note
    When I run "ticket dep guard-0001 guard-0002 --reason 'needs the parser'"
    Then the exit code should be 0
    And the output line 1 should contain "Added dependency: guard-0001 -> guard-0002"
    And the output line 2 should contain "Note: Blocked by guard-0002: needs the parser"
    And ticket "guard-0001" should contain "deps: [guard-0002]"
    And ticket "guard-0001" should contain "Blocked by guard-0002: needs the parser"
    And ticket "guard-0001" should contain a timestamp in notes

  Scenario: The note goes on the blocked ticket only
    When I run "ticket dep guard-0001 guard-0002 --reason 'needs the parser'"
    Then the exit code should be 0
    And ticket "guard-0002" should not contain "Blocked by"

  Scenario: --reason=<text> form
    When I run "ticket dep guard-0001 guard-0002 --reason='needs the parser'"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "Blocked by guard-0002: needs the parser"

  Scenario: Flags may come before the IDs
    When I run "ticket dep --reason 'needs the parser' guard-0001 guard-0002"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: [guard-0002]"
    And ticket "guard-0001" should contain "Blocked by guard-0002: needs the parser"

  Scenario: IDs after -- are taken literally
    When I run "ticket dep --no-note -- guard-0001 guard-0002"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: [guard-0002]"

  Scenario: dep --no-note adds the dependency without a note
    When I run "ticket dep guard-0001 guard-0002 --no-note"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: [guard-0002]"
    And ticket "guard-0001" should not contain "Blocked by"
    And the output should not contain "Note:"

  Scenario: undep writes the No longer blocked by note
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket undep guard-0001 guard-0002 --reason 'split out'"
    Then the exit code should be 0
    And the output line 1 should contain "Removed dependency: guard-0001 -/-> guard-0002"
    And the output line 2 should contain "Note: No longer blocked by guard-0002: split out"
    And ticket "guard-0001" should contain "deps: []"
    And ticket "guard-0001" should contain "No longer blocked by guard-0002: split out"

  Scenario: undep --no-note removes the dependency without a note
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket undep guard-0001 guard-0002 --no-note"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: []"
    And ticket "guard-0001" should not contain "No longer blocked by"

  # --- Usage errors ---

  Scenario: dep without --reason is a usage error
    When I run "ticket dep guard-0001 guard-0002"
    Then the exit code should be 2
    And the error output should contain "--reason <text> is required"
    And the error output should contain "Usage: tk dep"
    And ticket "guard-0001" should contain "deps: []"

  Scenario: undep without --reason is a usage error
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket undep guard-0001 guard-0002"
    Then the exit code should be 2
    And the error output should contain "--reason <text> is required"
    And the error output should contain "Usage: tk undep"
    And ticket "guard-0001" should contain "deps: [guard-0002]"

  Scenario: --reason with --no-note is a usage error
    When I run "ticket dep guard-0001 guard-0002 --reason 'x' --no-note"
    Then the exit code should be 2
    And the error output should contain "mutually exclusive"
    And ticket "guard-0001" should contain "deps: []"

  Scenario: Empty reason is a usage error
    When I run "ticket dep guard-0001 guard-0002 --reason ''"
    Then the exit code should be 2
    And the error output should contain "--reason must not be empty"
    And ticket "guard-0001" should contain "deps: []"

  Scenario: Unknown option is a usage error
    When I run "ticket dep guard-0001 guard-0002 --force"
    Then the exit code should be 2
    And the error output should contain "unknown option: --force"
    And ticket "guard-0001" should contain "deps: []"

  Scenario: One ID only is a usage error
    When I run "ticket dep guard-0001 --no-note"
    Then the exit code should be 2
    And the error output should contain "expected <id> and <dep-id>"

  Scenario: --help prints usage for the invoked command
    When I run "ticket undep --help"
    Then the exit code should be 0
    And the output should contain "Usage: tk undep"
    And the output should contain "tk super undep"

  # --- Existing state ---

  Scenario: Duplicate dependency is reported and gets no second note
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket dep guard-0001 guard-0002 --reason 'again'"
    Then the exit code should be 0
    And the output should contain "Dependency already exists"
    And ticket "guard-0001" should contain "deps: [guard-0002]"
    And ticket "guard-0001" should not contain "Blocked by"

  Scenario: undep of an absent dependency fails without a note
    When I run "ticket undep guard-0001 guard-0002 --reason 'gone'"
    Then the exit code should be 1
    And the output should contain "Dependency not found"
    And ticket "guard-0001" should not contain "No longer blocked by"

  Scenario: A dependency whose ID is a substring of an existing one is not mistaken for it
    Given a ticket exists with ID "abc-001" and title "Short"
    And a ticket exists with ID "abc-0012" and title "Long"
    And ticket "guard-0001" depends on "abc-0012"
    When I run "ticket dep guard-0001 abc-001 --reason 'needs short'"
    Then the exit code should be 1
    And the error output should contain "did not add abc-001 to guard-0001"
    And the output should not contain "Dependency already exists"
    And ticket "guard-0001" should contain "deps: [abc-0012]"
    And ticket "guard-0001" should not contain "Blocked by"

  # --- IDs ---

  Scenario: Partial IDs resolve to full IDs
    When I run "ticket dep 0001 0002 --reason 'needs the parser'"
    Then the exit code should be 0
    And the output should contain "Added dependency: guard-0001 -> guard-0002"
    And ticket "guard-0001" should contain "Blocked by guard-0002: needs the parser"

  Scenario: Nonexistent ticket
    When I run "ticket dep guard-0001 nonexistent --no-note"
    Then the exit code should be 1
    And the error output should contain "Error: ticket 'nonexistent' not found"

  Scenario: Ambiguous ticket
    When I run "ticket dep guard-0001 guard- --no-note"
    Then the exit code should be 1
    And the error output should contain "Error: ambiguous ID 'guard-' matches multiple tickets"

  # --- Pass-through and bypass ---

  Scenario: dep tree works through the plugin
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket dep tree guard-0001"
    Then the exit code should be 0
    And the output should contain "guard-0001"
    And the output should contain "guard-0002"

  Scenario: dep cycle works through the plugin
    When I run "ticket dep cycle"
    Then the exit code should be 0
    And the output should contain "No dependency cycles found"

  Scenario: tk super dep bypasses the guard
    When I run "ticket super dep guard-0001 guard-0001"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: [guard-0001]"
```

- [ ] **Step 3: Run it and watch it fail**

Run: `uv run --with behave behave features/ticket_dep_guard.feature`
Expected: failures. Without the plugin `ticket dep A A --reason ...` reaches the built-in, which ignores extra arguments and adds the self-dependency with exit 0, so "Self-dependency is rejected" fails on `the exit code should be 1`; the usage scenarios fail on exit code 2; the note scenarios fail on the missing `Note:` line. `dep tree`, `dep cycle` and `super dep` scenarios already pass (built-in behaviour) - they must keep passing.

- [ ] **Step 4: Write the plugin**

Create `plugins/ticket-dep`:

```bash
#!/usr/bin/env bash
# tk-plugin: Guarded dep/undep: reject self-deps and cycles, record the reason
# tk-plugin-version: 1.0.0
set -euo pipefail

# One script, two commands: plugins/ticket-undep is a symlink to this file
mode="${0##*/}"
mode="${mode#tk-}"
mode="${mode#ticket-}"
[[ "$mode" == "undep" ]] || mode="dep"

usage() {
    if [[ "$mode" == "dep" ]]; then
        echo "Usage: tk dep <id> <dep-id> (--reason <text> | --no-note)"
        echo "       tk dep tree [--full] <id>   show dependency tree"
        echo "       tk dep cycle                find dependency cycles"
    else
        echo "Usage: tk undep <id> <dep-id> (--reason <text> | --no-note)"
    fi
    echo "  --reason <text>  why the dependency changes; written as a note on <id>"
    echo "  --no-note        change the dependency without writing a note"
    echo "Bypass the guard: tk super $mode <id> <dep-id>"
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

# tree and cycle are not guarded: hand them to the built-in unchanged
if [[ "$mode" == "dep" && ( "${1:-}" == "tree" || "${1:-}" == "cycle" ) ]]; then
    exec "$TK_SCRIPT" super dep "$@"
fi

reason="" have_reason=0 no_note=0
ids=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --reason)
            [[ $# -ge 2 ]] || die_usage "--reason requires a text"
            reason="$2"; have_reason=1; shift 2 ;;
        --reason=*) reason="${1#--reason=}"; have_reason=1; shift ;;
        --no-note) no_note=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; while [[ $# -gt 0 ]]; do ids+=("$1"); shift; done ;;
        -*) die_usage "unknown option: $1" ;;
        *) ids+=("$1"); shift ;;
    esac
done

[[ ${#ids[@]} -eq 2 ]] || die_usage "expected <id> and <dep-id>"
if [[ $have_reason -eq 1 && $no_note -eq 1 ]]; then
    die_usage "--reason and --no-note are mutually exclusive"
fi
if [[ $have_reason -eq 0 && $no_note -eq 0 ]]; then
    die_usage "--reason <text> is required (or pass --no-note)"
fi
if [[ $have_reason -eq 1 && -z "${reason//[[:space:]]/}" ]]; then
    die_usage "--reason must not be empty"
fi

if [[ -z "${TICKETS_DIR:-}" || ! -d "$TICKETS_DIR" ]]; then
    echo "Error: no .tickets directory found (searched parent directories)" >&2
    exit 2
fi

# Full ID on stdout; same lookup and error texts as ticket_path in core
resolve_id() {
    local id="$1" matches count
    read -r id <<< "$id"
    if [[ -f "$TICKETS_DIR/$id.md" ]]; then
        echo "$id"
        return 0
    fi
    matches=$(find "$TICKETS_DIR" -maxdepth 1 -name "*${id}*.md" 2>/dev/null | head -2)
    count=$(printf '%s\n' "$matches" | grep -c . || true)
    if [[ "$count" -eq 1 ]]; then
        basename "$matches" .md
    elif [[ "$count" -gt 1 ]]; then
        echo "Error: ambiguous ID '$id' matches multiple tickets" >&2
        return 1
    else
        echo "Error: ticket '$id' not found" >&2
        return 1
    fi
}

# Front matter field of one ticket
field_of() {
    awk -v key="$2" '
    FNR == 1 { if ($0 != "---") exit; next }
    /^---$/ { exit }
    index($0, key ":") == 1 {
        v = substr($0, length(key) + 2)
        gsub(/^[ \t]+|[ \t]+$/, "", v)
        print v
        exit
    }' "$TICKETS_DIR/$1.md"
}

# deps of one ticket, one ID per line
deps_of() {
    field_of "$1" deps | awk '{
        gsub(/[][]/, ""); gsub(/[ \t]/, "")
        n = split($0, a, ",")
        for (i = 1; i <= n; i++) if (a[i] != "") print a[i]
    }'
}

# Exact element test (core matches substrings)
has_dep() {
    local d
    while IFS= read -r d; do
        [[ "$d" == "$2" ]] && return 0
    done < <(deps_of "$1")
    return 1
}

write_note() {
    "$TK_SCRIPT" super add-note "$1" "$2" >/dev/null
    echo "Note: $2"
}

id=$(resolve_id "${ids[0]}") || exit 1
dep_id=$(resolve_id "${ids[1]}") || exit 1

if [[ "$mode" == "dep" ]]; then
    if [[ "$id" == "$dep_id" ]]; then
        echo "Error: $id cannot depend on itself" >&2
        echo "Use 'tk super dep' to bypass the guard" >&2
        exit 1
    fi
    if has_dep "$id" "$dep_id"; then
        echo "Dependency already exists"
        exit 0
    fi
    out=$("$TK_SCRIPT" super dep "$id" "$dep_id") || { [[ -n "$out" ]] && echo "$out" >&2; exit 1; }
    if ! has_dep "$id" "$dep_id"; then
        echo "Error: tk super dep did not add $dep_id to $id (core matched it as a substring of an existing dependency)" >&2
        exit 1
    fi
    echo "$out"
    [[ $no_note -eq 1 ]] || write_note "$id" "Blocked by $dep_id: $reason"
else
    if ! has_dep "$id" "$dep_id"; then
        echo "Dependency not found"
        exit 1
    fi
    out=$("$TK_SCRIPT" super undep "$id" "$dep_id") || { [[ -n "$out" ]] && echo "$out" >&2; exit 1; }
    if has_dep "$id" "$dep_id"; then
        echo "Error: tk super undep did not remove $dep_id from $id" >&2
        exit 1
    fi
    echo "$out"
    [[ $no_note -eq 1 ]] || write_note "$id" "No longer blocked by $dep_id: $reason"
fi
```

Why `has_dep` is a `while read` loop and not `deps_of | grep -qx`: with `set -o pipefail`, `grep -q` exits at the first match, the writer gets SIGPIPE, and the pipeline reports failure for a dependency that IS present.

- [ ] **Step 5: Make it executable and add the symlink**

```bash
chmod +x plugins/ticket-dep
ln -s ticket-dep plugins/ticket-undep
```

Verify: `ls -l plugins/ticket-undep` shows `plugins/ticket-undep -> ticket-dep`.

- [ ] **Step 6: Run the feature**

Run: `uv run --with behave behave features/ticket_dep_guard.feature`
Expected: `1 feature passed, 0 failed`, `26 scenarios passed, 0 failed`.

- [ ] **Step 7: Run the whole suite**

Run: `make test`
Expected: `15 features passed, 0 failed`, `206 scenarios passed, 0 failed`. A failure in `ticket_dependencies.feature`, `id_resolution.feature` or `ticket_directory.feature` means Task 1 missed a line.

- [ ] **Step 8: Commit**

```bash
git add plugins/ticket-dep plugins/ticket-undep features/ticket_dep_guard.feature features/steps/ticket_steps.py
git commit -m "feat: add ticket-dep guard plugin with reason notes (tic-mwhy)"
```

---

### Task 3: Cycle guard

**Files:**
- Modify: `features/ticket_dep_guard.feature` (append scenarios)
- Modify: `plugins/ticket-dep` (one new function, one new block in dep mode)

**Interfaces:**
- Consumes: `has_dep`, globals `id`, `dep_id` from Task 2.
- Produces: `cycle_path <full-id> <dep-full-id>` - when `<id>` is reachable from `<dep-id>` through `deps` edges: prints `id -> dep-id -> ... -> id`, returns 0; otherwise returns 1; any other status is an awk failure.

- [ ] **Step 1: Append the failing scenarios**

Append to `features/ticket_dep_guard.feature`:

```gherkin

  # --- Cycles ---

  Scenario: Two-node cycle is rejected
    Given ticket "guard-0002" depends on "guard-0001"
    When I run "ticket dep guard-0001 guard-0002 --reason 'loop'"
    Then the exit code should be 1
    And the error output should contain "guard-0001 -> guard-0002 would create a cycle: guard-0001 -> guard-0002 -> guard-0001"
    And the error output should contain "tk super dep"
    And ticket "guard-0001" should contain "deps: []"
    And ticket "guard-0001" should not contain "Blocked by"

  Scenario: Three-node cycle is rejected
    Given ticket "guard-0002" depends on "guard-0003"
    And ticket "guard-0003" depends on "guard-0001"
    When I run "ticket dep guard-0001 guard-0002 --reason 'loop'"
    Then the exit code should be 1
    And the error output should contain "would create a cycle: guard-0001 -> guard-0002 -> guard-0003 -> guard-0001"
    And ticket "guard-0001" should contain "deps: []"
    And ticket "guard-0001" should not contain "Blocked by"

  Scenario: A cycle through a closed ticket is rejected
    Given ticket "guard-0002" depends on "guard-0003"
    And ticket "guard-0003" depends on "guard-0001"
    And ticket "guard-0003" has status "closed"
    When I run "ticket dep guard-0001 guard-0002 --reason 'loop'"
    Then the exit code should be 1
    And the error output should contain "would create a cycle"
    And ticket "guard-0001" should contain "deps: []"

  Scenario: A diamond is not a cycle
    Given a ticket exists with ID "guard-0004" and title "Fourth"
    And ticket "guard-0001" depends on "guard-0002"
    And ticket "guard-0001" depends on "guard-0003"
    And ticket "guard-0002" depends on "guard-0004"
    When I run "ticket dep guard-0003 guard-0004 --reason 'shared base'"
    Then the exit code should be 0
    And ticket "guard-0003" should contain "deps: [guard-0004]"

  Scenario: A dependency on a missing ticket file does not break the walk
    Given ticket "guard-0002" has raw field "deps" set to "[ghost-9999]"
    When I run "ticket dep guard-0001 guard-0002 --no-note"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: [guard-0002]"
```

- [ ] **Step 2: Run and watch the three cycle scenarios fail**

Run: `uv run --with behave behave features/ticket_dep_guard.feature`
Expected: "Two-node cycle is rejected", "Three-node cycle is rejected" and "A cycle through a closed ticket is rejected" FAIL on `the exit code should be 1` (the dependency is added, exit 0). "A diamond is not a cycle" and "A dependency on a missing ticket file ..." already pass; they guard against false positives and must still pass after Step 3.

- [ ] **Step 3: Add `cycle_path`**

In `plugins/ticket-dep`, insert this function directly after the closing `}` of `has_dep` (before `write_note`):

```bash

# Would <id> -> <dep-id> close a cycle? Walks deps from <dep-id>, every status:
# a closed ticket can be reopened, so it counts as an edge (like ticket-lint).
# Found: prints "id -> dep-id -> ... -> id", returns 0. Not found: returns 1.
cycle_path() {
    awk -v target="$1" -v from="$2" '
    FNR == 1 {
        n = split(FILENAME, parts, "/")
        cur = parts[n]
        sub(/\.md$/, "", cur)
        fm = ($0 == "---") ? 1 : 2
        next
    }
    fm == 1 && /^---$/ { fm = 2; next }
    fm == 1 && /^deps:/ {
        v = substr($0, index($0, ":") + 1)
        gsub(/[][]/, "", v); gsub(/[ \t]/, "", v)
        deps[cur] = v
    }
    END {
        head = 1; tail = 1; queue[1] = from; seen[from] = 1; found = 0
        while (head <= tail) {
            node = queue[head++]
            if (node == target) { found = 1; break }
            n = split(deps[node], a, ",")
            for (i = 1; i <= n; i++) if (a[i] != "" && !(a[i] in seen)) {
                seen[a[i]] = 1; parent[a[i]] = node; queue[++tail] = a[i]
            }
        }
        if (!found) exit 1
        path = target
        for (node = target; node != from; ) { node = parent[node]; path = node " -> " path }
        print target " -> " path
    }' "$TICKETS_DIR"/*.md
}
```

The walk is breadth-first, so the printed path is the shortest one. `deps[node]` for a missing ticket is an empty string: `split` returns 0 and the walk moves on.

- [ ] **Step 4: Call it in dep mode**

In `plugins/ticket-dep`, dep mode, insert between the `if has_dep ...; then ... fi` block ("Dependency already exists") and the line `out=$("$TK_SCRIPT" super dep ...`:

```bash
    rc=0
    path=$(cycle_path "$id" "$dep_id") || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "Error: $id -> $dep_id would create a cycle: $path" >&2
        echo "Use 'tk super dep' to bypass the guard" >&2
        exit 1
    elif [[ $rc -ne 1 ]]; then
        echo "Error: cycle check failed" >&2
        exit 1
    fi
```

- [ ] **Step 5: Run the feature**

Run: `uv run --with behave behave features/ticket_dep_guard.feature`
Expected: `31 scenarios passed, 0 failed`.

- [ ] **Step 6: Run the whole suite**

Run: `make test`
Expected: `15 features passed, 0 failed`, `211 scenarios passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add plugins/ticket-dep features/ticket_dep_guard.feature
git commit -m "feat: ticket-dep rejects dependency cycles (tic-mwhy)"
```

---

### Task 4: State line

**Files:**
- Modify: `features/ticket_dep_guard.feature` (append scenarios)
- Modify: `plugins/ticket-dep` (one new function, two call sites)

**Interfaces:**
- Consumes: `field_of`, `deps_of` from Task 2.
- Produces: `state_line <full-id>` - prints exactly one of `<id> is closed`, `<id> is ready`, `<id> is blocked by: <dep> [<status>], ...` (non-closed deps in `deps` order; missing file -> `[missing]`). It is the last stdout line of every successful `dep` / `undep`, including the "Dependency already exists" case.

- [ ] **Step 1: Append the failing scenarios**

Append to `features/ticket_dep_guard.feature`:

```gherkin

  # --- State line ---

  Scenario: dep prints the blocked state
    When I run "ticket dep guard-0001 guard-0002 --reason 'needs the parser'"
    Then the exit code should be 0
    And the output line 3 should contain "guard-0001 is blocked by: guard-0002 [open]"
    And the output line count should be 3

  Scenario: Every non-closed blocker is listed with its status
    Given ticket "guard-0001" depends on "guard-0002"
    And ticket "guard-0002" has status "in_progress"
    When I run "ticket dep guard-0001 guard-0003 --no-note"
    Then the exit code should be 0
    And the output line 2 should contain "guard-0001 is blocked by: guard-0002 [in_progress], guard-0003 [open]"

  Scenario: A closed dependency does not block
    Given ticket "guard-0002" has status "closed"
    When I run "ticket dep guard-0001 guard-0002 --no-note"
    Then the exit code should be 0
    And the output line 2 should contain "guard-0001 is ready"

  Scenario: undep of the last open blocker makes the ticket ready
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket undep guard-0001 guard-0002 --reason 'split out'"
    Then the exit code should be 0
    And the output line 3 should contain "guard-0001 is ready"

  Scenario: undep with another blocker left keeps the ticket blocked
    Given ticket "guard-0001" depends on "guard-0002"
    And ticket "guard-0001" depends on "guard-0003"
    When I run "ticket undep guard-0001 guard-0002 --no-note"
    Then the exit code should be 0
    And the output line 2 should contain "guard-0001 is blocked by: guard-0003 [open]"

  Scenario: A closed ticket is reported as closed
    Given ticket "guard-0001" has status "closed"
    When I run "ticket dep guard-0001 guard-0002 --no-note"
    Then the exit code should be 0
    And the output line 2 should contain "guard-0001 is closed"

  Scenario: A dependency without a ticket file is listed as missing
    Given ticket "guard-0001" has raw field "deps" set to "[ghost-9999]"
    When I run "ticket dep guard-0001 guard-0002 --no-note"
    Then the exit code should be 0
    And the output line 2 should contain "guard-0001 is blocked by: ghost-9999 [missing], guard-0002 [open]"

  Scenario: Duplicate dependency still prints the state
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket dep guard-0001 guard-0002 --reason 'again'"
    Then the exit code should be 0
    And the output line 1 should contain "Dependency already exists"
    And the output line 2 should contain "guard-0001 is blocked by: guard-0002 [open]"
```

- [ ] **Step 2: Run and watch them fail**

Run: `uv run --with behave behave features/ticket_dep_guard.feature`
Expected: the 8 new scenarios FAIL with `Output has only N lines, expected at least ...`.

- [ ] **Step 3: Add `state_line`**

In `plugins/ticket-dep`, insert directly after the closing `}` of `write_note`:

```bash

# Last output line: is <id> ready, blocked (by what) or closed?
state_line() {
    local id="$1" d st blockers=""
    if [[ "$(field_of "$id" status)" == "closed" ]]; then
        echo "$id is closed"
        return 0
    fi
    while IFS= read -r d; do
        if [[ -f "$TICKETS_DIR/$d.md" ]]; then st=$(field_of "$d" status); else st="missing"; fi
        [[ "$st" == "closed" ]] && continue
        blockers+="${blockers:+, }$d [$st]"
    done < <(deps_of "$id")
    if [[ -n "$blockers" ]]; then
        echo "$id is blocked by: $blockers"
    else
        echo "$id is ready"
    fi
}
```

- [ ] **Step 4: Call it**

Two edits in `plugins/ticket-dep`:

1. In dep mode, the duplicate block becomes:

```bash
    if has_dep "$id" "$dep_id"; then
        echo "Dependency already exists"
        state_line "$id"
        exit 0
    fi
```

2. Append as the very last line of the file, after the closing `fi` of the `if [[ "$mode" == "dep" ]]; then ... else ... fi` block:

```bash
state_line "$id"
```

- [ ] **Step 5: Run the feature**

Run: `uv run --with behave behave features/ticket_dep_guard.feature`
Expected: `39 scenarios passed, 0 failed`.

- [ ] **Step 6: Run the whole suite**

Run: `make test`
Expected: `15 features passed, 0 failed`, `219 scenarios passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add plugins/ticket-dep features/ticket_dep_guard.feature
git commit -m "feat: ticket-dep prints ready/blocked state line (tic-mwhy)"
```

---

### Task 5: Documentation and skill

**Files:**
- Modify: `README.md` (usage block, "Official plugins" paragraph)
- Modify: `plugins/README.md` (new section before `## ticket-find`)
- Modify: `CHANGELOG.md` (`## [Unreleased]` -> `### Plugins`)
- Modify: `skills/managing-tk-tickets/SKILL.md` (quick reference row, Creating step 4, one Common mistakes row)
- Modify: `skills/managing-tk-tickets/editing.md` (third bullet of step 3)

**Interfaces:**
- Consumes: the finished CLI from Tasks 2-4.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: README usage block**

In `README.md`, inside the usage code block, under the line `Official plugins (installed separately):`, insert these lines before the `  find ...` line:

```
  dep <id> <dep-id> --reason X     Guarded dep (shadows the built-in): rejects self-deps and
                           cycles, notes 'Blocked by <dep-id>: X', prints ready/blocked state
  undep <id> <dep-id> --reason X   Guarded undep: notes 'No longer blocked by <dep-id>: X'
                           (--no-note instead of --reason skips the note; dep tree / dep cycle unchanged)
```

- [ ] **Step 2: README "Official plugins" paragraph**

In the paragraph starting `**Official plugins** live in`, replace the last sentence

```
Neither is part of `ticket-extras`: copy or symlink `plugins/ticket-lint` and `plugins/ticket-find` into your PATH, or install the `ticket-lint` and `ticket-find` packages.
```

with

```
`ticket-dep` (with its `ticket-undep` symlink) shadows the built-in `tk dep` / `tk undep`: it rejects self-dependencies and cycles and requires a `--reason`, which it records as a note on the blocked ticket; `tk super dep` bypasses it. None of them is part of `ticket-extras`: copy or symlink them from `plugins/` into your PATH, or install the `ticket-lint`, `ticket-find` and `ticket-dep` packages.
```

- [ ] **Step 3: `plugins/README.md` section**

Insert before the line `## ticket-find`:

````markdown
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

````

- [ ] **Step 4: CHANGELOG**

In `CHANGELOG.md`, under `## [Unreleased]` -> `### Plugins`, append after the `ticket-find 1.0.0` line:

```
- ticket-dep 1.0.0: New plugin, shadows `tk dep` / `tk undep` (`ticket-undep` is a symlink to it): rejects self-dependencies and cycles (closed tickets count as edges), compares dependency IDs exactly, requires `--reason <text>` (or `--no-note`) and writes `Blocked by <dep-id>: <text>` / `No longer blocked by <dep-id>: <text>`, prints whether the ticket is ready or blocked; `tk dep tree` / `tk dep cycle` pass through; bypass with `tk super dep`
```

- [ ] **Step 5: `SKILL.md`**

Three replacements in `skills/managing-tk-tickets/SKILL.md`:

1. Quick reference row

```
| Hard blocker / soft relation | `tk dep <blocked> <blocker>` / `tk link <a> <b>` |
```

becomes

```
| Hard blocker / soft relation | `tk dep <blocked> <blocker> --reason "<why>"` / `tk link <a> <b>` |
```

2. Creating step 4

```
4. After every dep: `tk add-note <blocked> "Blocked by <id>: <reason>"`.
```

becomes

```
4. Every dep carries its reason: `tk dep <blocked> <blocker> --reason "<reason>"` writes the `Blocked by <id>: <reason>` note and refuses self-deps and cycles (`tk undep ... --reason` writes `No longer blocked by`). No `Note:` line in the output -> the ticket-dep plugin is not installed: `tk add-note <blocked> "Blocked by <id>: <reason>"` yourself.
```

3. Common mistakes row

```
| Dep without a reason | `Blocked by <id>: <reason>` note |
```

becomes

```
| Dep without a reason | `tk dep ... --reason`; no plugin -> `Blocked by <id>: <reason>` note |
```

Everything else in the skill stays (its rewrite is `tic-x75b`).

- [ ] **Step 6: `editing.md`**

In `skills/managing-tk-tickets/editing.md`, step 3, replace the bullet

```
   - Every change gets a note on the blocked ticket: `Blocked by <id>: <reason>` / `No longer blocked by <id>: <reason>`.
```

with

```
   - Every change gets a note on the blocked ticket: `tk dep ... --reason "<reason>"` / `tk undep ... --reason "<reason>"` write `Blocked by <id>: <reason>` / `No longer blocked by <id>: <reason>`. No `Note:` line in the output (plugin not installed) -> `tk add-note` by hand.
```

- [ ] **Step 7: Check `tk help` and the extras list**

Run: `PATH="/home/namli/www/ticket/.claude/worktrees/tic-mwhy-guarded-dep/plugins:$PATH" ./ticket help`
Expected: under "Plugins", both `dep` and `undep` with the description `Guarded dep/undep: reject self-deps and cycles, record the reason`.

Run: `git diff --stat master -- pkg/extras.txt`
Expected: no output (`pkg/extras.txt` untouched).

- [ ] **Step 8: Run the suite**

Run: `make test`
Expected: `15 features passed, 0 failed`, `219 scenarios passed, 0 failed`.

- [ ] **Step 9: Commit**

```bash
git add README.md plugins/README.md CHANGELOG.md skills/managing-tk-tickets/SKILL.md skills/managing-tk-tickets/editing.md
git commit -m "docs: document ticket-dep guard, point the skill at --reason (tic-mwhy)"
```

---

### Task 6: Portability check, dogfooding, handoff

**Files:** none created in the repository.

**Interfaces:**
- Consumes: everything above.
- Produces: evidence for closing `tic-mwhy`; the close itself needs the user's explicit yes.

- [ ] **Step 1: Run the guard feature under busybox awk**

Create `bb-dep-guard.sh` in the session scratchpad directory (NOT in the repository):

```bash
#!/usr/bin/env bash
# Run the guard feature with busybox awk shadowing the system awk
WT=/home/namli/www/ticket/.claude/worktrees/tic-mwhy-guarded-dep
BB=$(mktemp -d)
ln -s "$(command -v busybox)" "$BB/awk"
export PATH="$BB:$PATH"
awk 2>&1 | head -1
cd "$WT" || exit 1
uv run --with behave behave features/ticket_dep_guard.feature 2>&1 | tail -5
rm -rf "$BB"
```

Run: `bash <scratchpad>/bb-dep-guard.sh`
Expected: first line starts with `BusyBox`, then `39 scenarios passed, 0 failed`. If `busybox` is not installed, record "busybox awk: not executed" for the PR text and continue.

- [ ] **Step 2: Dogfood on this repository's tickets**

Run each as a separate command, with `plugins/` on `PATH`:

```bash
PATH="/home/namli/www/ticket/.claude/worktrees/tic-mwhy-guarded-dep/plugins:$PATH" ./ticket dep tic-mwhy tic-mwhy --reason "self"
PATH="/home/namli/www/ticket/.claude/worktrees/tic-mwhy-guarded-dep/plugins:$PATH" ./ticket dep tic-mwhy tic-x75b --reason "cycle probe"
git status --short .tickets/
```

Expected: the first prints `Error: tic-mwhy cannot depend on itself`, exit 1; the second prints `would create a cycle: tic-mwhy -> tic-x75b -> tic-mwhy` (tic-x75b already depends on tic-mwhy), exit 1; `git status` shows no change caused by these two commands.

- [ ] **Step 3: Check the acceptance criteria of `tic-mwhy` one by one**

Run: `./ticket show tic-mwhy` and tick each criterion against the feature file: self-dep rejected; 2- and 3-node cycle rejected and file unchanged; note written with exact prefix; dep tree / dep cycle work through the plugin; undep note written; state line printed; `make test` passes; README usage block, `plugins/README.md`, `CHANGELOG.md` updated; metadata present; not in `pkg/extras.txt`.

- [ ] **Step 4: Report and ask**

Report to the user: test counts, the busybox result, what was not executed (gawk, BSD awk, bash 3.2), and that a follow-up ticket may be wanted for the core substring match in `cmd_dep` / `cmd_undep` (`ticket`, `_grep -q "$dep_id"`), which the plugin only reports. State which tickets closing `tic-mwhy` would unblock: `tic-o862` and `tic-x75b` list it as a blocker - check with `./ticket show` whether they have other open blockers. Then STOP and ask whether to close `tic-mwhy`; on yes follow the Closing section of the `managing-tk-tickets` skill (`Closed: done - ...` note, `./ticket close`, stage `.tickets/` last, commit), then offer push and PR.
