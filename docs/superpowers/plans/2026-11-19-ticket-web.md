# ticket-web Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `tk web` plugin: a local HTTP server that shows the tickets of several configured tk projects in four columns and lets the owner edit the title and text of a ticket.

**Architecture:** One executable Python file, `plugins/ticket-web`. It parses `.tickets/*.md` itself, asks `tk blocked` for the blocked set, renders HTML on the server, and embeds its CSS and JavaScript as strings. A `Store` keeps one snapshot per project; every request and a one-second watcher thread call the same `refresh`, and the watcher wakes the SSE clients. Writes go through `tk set` (title) and an in-place section replace (text).

**Tech Stack:** Python 3.11+ standard library (`http.server`, `tomllib`, `subprocess`, `hashlib`, `threading`, `html`); plain JavaScript (`EventSource`, `fetch`); tests in Behave, run with `make test`.

**Spec:** `docs/superpowers/specs/2026-11-19-ticket-web-design.md` - read it before starting. Where this plan and the spec differ, stop and ask.

**Ticket:** `tic-rceq`. Branch: `tic-rceq-web-kanban-board` (exists; spec and this plan are on it).

## Global Constraints

- Python 3.11 or newer. Standard library only. No third-party file in the repository.
- One file: `plugins/ticket-web`, mode 755. Line 1 `#!/usr/bin/env python3`, line 2 `# tk-plugin: Local kanban board over several tk projects`, line 3 `# tk-plugin-version: 1.0.0`.
- Add no other file that matches `plugins/ticket-*`.
- Do not modify `ticket`, `scripts/`, `pkg/`. Do not add `web` to `pkg/extras.txt`.
- The server binds `127.0.0.1` only.
- The server never passes `--force` and never calls `tk super`.
- The server writes only: the title (through `tk set`), and the description, `Design` and `Acceptance Criteria` text.
- Every `tk` call: argument list (no shell), `cwd` = project path, env `TICKETS_DIR=<path>/.tickets`. Program: `$TK_SCRIPT`, else `tk` from PATH.
- UI text is English. Column titles: `Blocked`, `Ready`, `In progress`, `Closed`.
- Every ticket and config value is passed through `html.escape` before it enters HTML.
- Responses are `text/html; charset=utf-8`. Files are read and written as UTF-8.
- Commit messages: conventional prefix, no attribution trailers of any kind.
- This project tracks work with `tk`. Load the `managing-tk-tickets` skill before any `tk` state change and before every commit. Never run `tk close` without the user's explicit yes. Stage `.tickets/` last.

## Review Focus

1. **Non-ASCII text.** A Russian title or description renders and saves unchanged (the owner writes Russian). Test in Task 2 and Task 4.
2. **HTML in ticket text.** A title `<script>alert(1)</script> & co` appears escaped, never as a tag. Test in Task 2.
3. **A file that is not valid UTF-8 or has no front matter.** The board still renders; that file is an `unparsable` card; its edit form returns 404. Test in Task 2.
4. **The ticket file disappears between form and save** (branch switch, agent delete). The save answers 404, not 500. Test in Task 4.
5. **An SSE client disconnects.** The server keeps serving; a later GET returns 200. Test in Task 5.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `plugins/ticket-web` | create, mode 755 | the whole plugin |
| `features/ticket_web.feature` | create | all scenarios |
| `features/steps/web_steps.py` | create | project fixtures, server start/stop, HTTP, HTML assertions |
| `features/environment.py` | modify `after_scenario` | stop a running web server |
| `README.md`, `plugins/README.md`, `CHANGELOG.md` | modify | documentation (Task 6) |

Test harness facts:

- `features/environment.py` puts `plugins/` on PATH. `ticket web` in a scenario resolves to `plugins/ticket-web`, and `tk set` inside the server finds `plugins/ticket-set`.
- Each scenario runs in a fresh `context.test_dir`.
- `features/steps/ticket_steps.py` uses `use_step_matcher("re")`. Call it at the top of `web_steps.py` too.
- Existing steps to reuse: `I run "ticket ..."`, `the exit code should be N`, `the command should fail`, `the output should contain "..."` (searches stdout + stderr).

### Names shared by all tasks

Sections of `plugins/ticket-web`, in file order:

```python
class ConfigError(Exception): ...
@dataclass
class Project:  name: str; path: Path; color: str
@dataclass
class Config:   port: int | None; projects: list[Project]
def load_config(path: Path) -> Config                      # raises ConfigError

@dataclass
class Ticket:
    id: str; file: str; parsed: bool
    status: str; type: str; priority: int; assignee: str; created: str; parent: str
    deps: list[str]; links: list[str]; tags: list[str]
    title: str; description: str; design: str; acceptance: str
    others: list[tuple[str, str]]      # (heading, text) of unknown '## ' sections
    notes: str; last_note: str         # last_note: ISO timestamp of the last note, '' when none
def parse_ticket(text: str, filename: str) -> Ticket       # never raises; parsed=False on failure

@dataclass
class Snapshot: tickets: dict[str, Ticket]; blocked: set[str]; error: str; stamp: frozenset
def run_tk(project: Project, *args: str) -> subprocess.CompletedProcess
def build_snapshot(project: Project) -> Snapshot

class Store:
    def __init__(self, projects: list[Project])
    def refresh(self, name: str) -> bool        # rebuild when the stamp changed; True when rebuilt
    def get(self, name: str) -> Snapshot        # calls refresh first
    def lock(self, name: str) -> threading.Lock # per-project write lock
    def wait_change(self, seen: int, timeout: float) -> int   # version counter for SSE
    def watch(self) -> None                     # loop: refresh all, bump version, sleep 1 s

def column_of(t: Ticket, blocked: set[str]) -> str   # 'blocked' | 'ready' | 'in_progress' | 'closed'
def edit_hash(title: str, description: str, design: str, acceptance: str) -> str
def replace_sections(text: str, description: str | None, design: str | None, acceptance: str | None) -> str
```

HTML hooks. Tests and the page script rely on them; do not rename.

| Element | Markup |
|---|---|
| Page body | `<header>` (nav + `<input id="q" type="search">`) then `<main>` |
| Lane | `<div class="lane" data-project="NAME">` with `<span class="count">N open</span>` |
| Lane error | `<div class="lane-error">TEXT</div>` inside the lane |
| Column | `<section class="col" data-col="blocked">` (`ready`, `in_progress`, `closed`) |
| Card | `<a class="card" data-project="NAME" data-id="ID" href="/p/NAME/ID">`; add class `is-blocked` for a blocked in-progress ticket |
| Unparsable card | `<div class="card unparsable">FILE unparsable</div>` in `ready` |
| More link | `<a class="more" href="/p/NAME">N more</a>` |
| Ticket relations | `<ul data-rel="parent">` (`children`, `deps`, `dependents`, `links`), one `<a>` per ticket |
| Ticket text | `<pre data-section="description">` (`design`, `acceptance`, `notes`) |
| Form | `<form method="post">` with `name="title"`, `description`, `design`, `acceptance`, hidden `base` |
| Conflict text | `<pre class="disk" data-field="description">` under the field |
| Form message | `<p class="msg">TEXT</p>` |

---

### Task 1: Server skeleton, config, CLI, test harness

**Files:**
- Create: `plugins/ticket-web`, `features/ticket_web.feature`, `features/steps/web_steps.py`
- Modify: `features/environment.py` (`after_scenario`)

**Interfaces:**
- Produces: `ConfigError`, `Project`, `Config`, `load_config`, `main(argv)`, the request handler with the Host check, the `page(title: str, main_html: str) -> str` wrapper, and every step listed below.

- [ ] **Step 1: Mark the ticket started**

Run: `tk start tic-rceq`
Expected: the ticket is `in_progress`.

- [ ] **Step 2: Write the steps in `features/steps/web_steps.py`**

| Step | Behaviour |
|---|---|
| `Given a web project "NAME"` | create `<test_dir>/NAME/.tickets/`; append NAME to `context.web_projects` |
| `Given a web project "NAME" without a tickets directory` | create `<test_dir>/NAME/` only; register it |
| `Given web project "NAME" has tickets:` (table) | columns `id` (required), `title` (default = id), `status` (`open`), `priority` (`2`), `type` (`task`), `deps` (space-separated, written as `[a, b]`), `parent`, `tags`, `last_note` (ISO timestamp: adds `## Notes` with one note `Closed: done`). File layout: the one in the spec, description line `Description of <id>`. |
| `Given web ticket "NAME/ID" has content:` (doc string) | write the doc string as the whole file |
| `Given web ticket "NAME/ID" has raw bytes "HEX"` | write `bytes.fromhex(HEX)` |
| `Given the web server is running` | write `<test_dir>/web.toml` with all registered projects; start `[ticket_script, 'web', '--port', '0', '--config', <path>]` with `Popen` (`cwd=test_dir`, stdout pipe, text mode); read the first stdout line; store `context.web_proc`, `context.web_port`, `context.web_base` |
| `Given the web server is running with the config in TK_WEB_CONFIG` | same, but no `--config`; pass the path in env `TK_WEB_CONFIG` |
| `When I GET "PATH"` / `When I GET "PATH" with header "K: V"` | `http.client.HTTPConnection('127.0.0.1', port)`; no redirect following; store `context.web_status`, `context.web_headers`, `context.web_body` (decoded UTF-8) |
| `When I open the edit form of "NAME/ID"` | GET `/p/NAME/ID/edit`; parse the form with `html.parser` into `context.web_form` (dict of the five fields); store the file bytes in `context.web_file_before` |
| `When I submit the form with:` (table `field`, `value`) / `... with header "K: V"` | copy `context.web_form`, apply the table (`\n` in a value means a line break), POST urlencoded to `/p/NAME/ID/edit` |
| `When web ticket "NAME/ID" file has "OLD" replaced by "NEW"` | rewrite the file |
| `When a note "TEXT" is appended to web ticket "NAME/ID"` | append `\n## Notes\n\n**2026-01-01T00:00:00Z**\n\nTEXT\n` (only the note part when `## Notes` exists) |
| `When web ticket "NAME/ID" is deleted` | unlink the file |
| `When I start a second web server on the same port` | run `ticket web --port <port> --config <path>` with `subprocess.run(timeout=10)`; fill `context.returncode`, `context.stdout`, `context.stderr` |
| `Then the response status should be N` | compare |
| `Then the response should contain "TEXT"` / `should not contain` | substring of `context.web_body` |
| `Then the response header "K" should be "V"` | compare |
| `Then project "NAME" column "COL" should list "ID1, ID2"` | parse `context.web_body`: card ids inside lane NAME, column COL, in document order; `""` means none |
| `Then column "COL" should list "NAME/ID1, NAME/ID2"` | flat view: `data-project/data-id` of the cards in column COL, in order |
| `Then relation "REL" should list "ID1, ID2"` | link texts inside `<ul data-rel="REL">` |
| `Then the lane of project "NAME" should show an error containing "TEXT"` | text of `.lane-error` in that lane |
| `Then web ticket "NAME/ID" file should contain "TEXT"` / `should not contain` | read the file |
| `Then web ticket "NAME/ID" file should be:` (doc string) | exact comparison |
| `Then web ticket "NAME/ID" file should be unchanged` | bytes equal `context.web_file_before` |
| `Then web ticket "NAME/ID" front matter and notes should be unchanged` | compare the text up to and including the second `---` line, and the text from `## Notes` to the end, with `context.web_file_before` |
| `Then GET "PATH" should eventually contain "TEXT"` | poll every 0.2 s, fail after 5 s |

In `features/environment.py` `after_scenario`: when `context.web_proc` exists, `terminate()`, `wait(5)`, then `kill()` on timeout.

- [ ] **Step 3: Write the failing scenarios in `features/ticket_web.feature`**

```gherkin
Feature: Web board
  As the owner of several tk projects
  I want one local page with the tickets of all of them
  So that I see what is ready and what is blocked

  Scenario: tk help lists the plugin
    When I run "ticket help"
    Then the output should contain "web"
    And the output should contain "Local kanban board over several tk projects"

  Scenario: A missing config stops the server
    When I run "ticket web --config /nonexistent/web.toml"
    Then the exit code should be 1
    And the output should contain "/nonexistent/web.toml"
    And the output should contain "[[project]]"

  Scenario: The server lists the configured projects
    Given a web project "alpha"
    And a web project "beta"
    And the web server is running
    When I GET "/"
    Then the response status should be 200
    And the response should contain "data-project=\"alpha\""
    And the response should contain "data-project=\"beta\""

  Scenario: The config path comes from TK_WEB_CONFIG
    Given a web project "alpha"
    And the web server is running with the config in TK_WEB_CONFIG
    When I GET "/"
    Then the response status should be 200

  Scenario: A foreign Host header is rejected
    Given a web project "alpha"
    And the web server is running
    When I GET "/" with header "Host: evil.example"
    Then the response status should be 403

  Scenario: An unknown path is not found
    Given a web project "alpha"
    And the web server is running
    When I GET "/nope"
    Then the response status should be 404

  Scenario: A busy port stops the second server
    Given a web project "alpha"
    And the web server is running
    When I start a second web server on the same port
    Then the exit code should be 1
```

Step texts cannot hold a raw double quote; if `\"` does not match in the existing matcher, assert `data-project=alpha` through the lane step instead (`project "alpha" column "ready" should list ""`).

Add two config scenarios that write a config by hand through a doc-string step `Given a web config:` and then run `ticket web --config web.toml`: a duplicate project name, and a name `a/b`. Both: exit code 1, output names the bad value.

- [ ] **Step 4: Run to see them fail**

Run: `uv run --with behave behave features/ticket_web.feature`
Expected: every scenario fails; the first failure is `tk help` not listing `web` or `ticket web` unknown.

- [ ] **Step 5: Implement the skeleton in `plugins/ticket-web`**

- `load_config(path)`: `tomllib`; rules from the spec section "Config". `ConfigError` messages name the path and the bad value. Expand `~` in `path`. Default color: `hsl(<h>, 55%, 45%)` with `h = zlib.crc32(name.encode()) % 360`.
- `main(argv)`: `argparse` with `--port`, `--config`. Config path order: `--config`, `$TK_WEB_CONFIG`, `~/.config/ticket/web.toml`. Port order: `--port`, config `port`, `7420`. On `ConfigError`: print the message and the example config from the spec to stderr, exit 1. On `OSError` from bind: `tk web: cannot listen on 127.0.0.1:<port>: <reason>` on stderr, exit 1.
- Server: `ThreadingHTTPServer(('127.0.0.1', port), Handler)`, `daemon_threads = True`. After bind print `tk web: http://127.0.0.1:<real port>/` with `flush=True`. Exit 0 on `KeyboardInterrupt` and on SIGTERM.
- `Handler`: before routing, the `Host` header must equal `127.0.0.1:<port>` or `localhost:<port>`, else 403. Silence `log_message`. Unknown route: 404. Any uncaught exception: 500 with the exception text, server stays up.
- `GET /`: one empty lane per project (columns come in Task 2).

- [ ] **Step 6: Run to see them pass**

Run: `uv run --with behave behave features/ticket_web.feature`
Expected: all scenarios pass.

- [ ] **Step 7: Commit**

```bash
git add plugins/ticket-web features/ticket_web.feature features/steps/web_steps.py features/environment.py
git add .tickets/
git commit -m "feat: add ticket-web skeleton with config and CLI"
```

---

### Task 2: Ticket parsing, snapshots, board pages

**Files:**
- Modify: `plugins/ticket-web`, `features/ticket_web.feature`

**Interfaces:**
- Consumes: `Project`, `Config`, `page`, the handler.
- Produces: `Ticket`, `parse_ticket`, `Snapshot`, `run_tk`, `build_snapshot`, `Store` (`refresh`, `get`, `lock`), `column_of`, routes `/`, `/?flat=1`, `/p/<name>`.

- [ ] **Step 1: Write the failing scenarios**

Background for this group:

```gherkin
    Given a web project "alpha"
    And web project "alpha" has tickets:
      | id     | title          | status      | priority | deps   | last_note            |
      | a-0001 | Open low       | open        | 3        |        |                      |
      | a-0002 | Open high      | open        | 1        |        |                      |
      | a-0003 | Waits          | open        | 2        | a-0001 |                      |
      | a-0004 | Working        | in_progress | 2        |        |                      |
      | a-0005 | Working waits  | in_progress | 2        | a-0001 |                      |
      | a-0006 | Old close      | closed      | 2        |        | 2026-01-01T00:00:00Z |
      | a-0007 | New close      | closed      | 2        |        | 2026-03-01T00:00:00Z |
      | a-0008 | Legacy done    | done        | 2        |        | 2026-02-01T00:00:00Z |
    And a web project "beta"
    And web project "beta" has tickets:
      | id     | title      |
      | a-0001 | Beta first |
    And the web server is running
```

Scenarios and their assertions:

| Scenario | Assertions |
|---|---|
| Columns on `/` | alpha `blocked` = `a-0003`; `ready` = `a-0002, a-0001`; `in_progress` = `a-0004, a-0005`; `closed` = `a-0007, a-0008, a-0006`; the alpha lane shows `5 open`, the beta lane shows `1 open` |
| Blocked in-progress mark | the card `a-0005` has class `is-blocked`; `a-0004` does not (add a step `card "NAME/ID" should have class "C"` / `should not have class`) |
| Card content | response contains `Open high`, `P1`, and for `a-0003` the blocker id `a-0001` inside its card |
| Same id in two projects | beta `ready` = `a-0001`; response contains `/p/alpha/a-0001` and `/p/beta/a-0001` |
| Flat view | GET `/?flat=1`: `ready` = `alpha/a-0002, alpha/a-0001, beta/a-0001` (priority, then id, then config order); no `class="lane"` in the response; each card shows its project name |
| Project page | GET `/p/alpha`: 200, same four columns for alpha; GET `/p/nope`: 404 |
| Closed limit | project with 7 closed tickets: `/` lists the 5 newest and contains `2 more`; `/p/<name>` lists all 7 |
| Project page limit | project with 52 closed tickets: `/p/<name>` lists 50 and contains `2 more` linking to `?closed=all`; `/p/<name>?closed=all` lists 52 |
| Missing `.tickets` | `Given a web project "gone" without a tickets directory`: its lane shows an error containing `.tickets`; alpha still lists its cards |
| Empty project | a project with no ticket file: lane present, all columns empty, no `lane-error` |
| Unknown status | status `review`: card in `ready`, response contains `review` |
| Change on disk | replace `Open low` by `Renamed low` in the file; `GET "/" should eventually contain "Renamed low"` |
| Review Focus 1 | title `Починить поиск`: response contains it literally |
| Review Focus 2 | title `<script>alert(1)</script> & co`: response contains `&lt;script&gt;alert(1)&lt;/script&gt; &amp; co` and not `<script>alert(1)` |
| Review Focus 3 | raw bytes `fffe00ff` in `alpha/bad-0001`, and a file `alpha/nofm-0001` with content `just text`: `/` is 200, contains `bad-0001.md unparsable` and `nofm-0001.md unparsable`, alpha `ready` still lists its tickets |

- [ ] **Step 2: Run to see them fail**

Run: `uv run --with behave behave features/ticket_web.feature`
Expected: the Task 1 scenarios pass, the new ones fail on empty columns.

- [ ] **Step 3: Implement parsing**

`parse_ticket(text, filename)`:
- Front matter = lines between the first two lines equal to `---`. The first line of the file must be `---`, and `id` must be present; otherwise `parsed=False`, `id` = filename without `.md`.
- `key: value` split at the first `: `. Lists: strip `[` `]`, split on `,`, strip blanks. `priority`: `int`, default 2 on failure. `type` default `task`.
- Body = lines after the closing `---`. Title = first line starting with `# `. Sections split at lines starting with `## `. Text before the first `## ` (after the title) = description. Headings `Design`, `Acceptance Criteria`, `Notes` fill their fields; any other goes to `others`. Every section text is stored without leading and trailing blank lines.
- `last_note` = the last match of `^\*\*(\d{4}-\d{2}-\d{2}T[\d:]+Z)\*\*$` in `notes`.

Read files with `encoding='utf-8'`; on `UnicodeDecodeError` produce the unparsable ticket.

- [ ] **Step 4: Implement snapshots and the store**

- `build_snapshot`: missing `<path>/.tickets` -> `error = "<path>/.tickets not found"`. Parse every `*.md`. No `*.md` file -> skip `tk blocked`, empty blocked set. Else `run_tk(project, 'blocked')`; non-zero exit -> `error = "tk blocked failed (exit N): <stderr>"`; else blocked = first word of each stdout line.
- `stamp` = frozenset of `(name, st_mtime_ns, st_size)` for every `*.md`, plus a marker for a missing directory.
- `Store.refresh(name)` computes the stamp, rebuilds when it differs. `get` calls `refresh`. One internal lock guards the snapshot dict.
- `column_of`: `closed` and `done` -> `closed`; `in_progress` -> `in_progress`; otherwise `blocked` when the id is in the blocked set, else `ready`.

- [ ] **Step 5: Implement the board pages**

- Order: `blocked`, `ready`, `in_progress` by `(priority, id)`. `closed` by `last_note or created`, descending, then id.
- `/`: 5 closed per lane plus the more link. `/?flat=1`: one set of columns; cards of all projects merged with the same sort keys (ties: config order); 5 closed per project. `/p/<name>`: 50 closed; `?closed=all` removes the limit; more link href `/p/<name>?closed=all`.
- Card text: id, title, `P<priority>`, type, tags, open blockers (deps whose ticket is absent or not in column `closed`), parent id; in the flat view also the project name with its color.
- Header nav: `/`, `/?flat=1`, one link per project.

- [ ] **Step 6: Run to see them pass**

Run: `uv run --with behave behave features/ticket_web.feature`
Expected: all scenarios pass.

- [ ] **Step 7: Commit**

```bash
git add plugins/ticket-web features/ticket_web.feature features/steps/web_steps.py
git commit -m "feat: ticket-web board pages with four columns"
```

---

### Task 3: Ticket page

**Files:**
- Modify: `plugins/ticket-web`, `features/ticket_web.feature`

**Interfaces:**
- Consumes: `Store.get`, `Ticket`, `column_of`, `page`.
- Produces: route `GET /p/<name>/<id>`.

- [ ] **Step 1: Write the failing scenarios**

Fixture: project `alpha` with `a-0001` (epic, parent of `a-0002`), `a-0002` (deps `a-0003`, links `a-0004`, tags `ui api`), `a-0003` (closed), `a-0004`; `a-0002` written with `web ticket ... has content:` so that it holds a description, `## Design`, `## Acceptance Criteria`, a section `## Risks`, and `## Notes` with one note.

| Scenario | Assertions |
|---|---|
| Text | GET `/p/alpha/a-0002`: 200; contains the title, the description, design, acceptance, `Risks` section and note text |
| Relations | `parent` = `a-0001`; `deps` = `a-0003`; `links` = `a-0004`; on `/p/alpha/a-0001` `children` = `a-0002`; on `/p/alpha/a-0003` `dependents` = `a-0002` |
| Dep status | the `deps` list item of `a-0003` contains `closed` |
| Dangling dep | a dep id with no file is shown as text with the word `missing`, not as a link |
| Edit link | response contains `/p/alpha/a-0002/edit` |
| Not found | GET `/p/alpha/zzz`, `/p/nope/a-0001`, `/p/alpha/..%2Fweb.toml`: 404 |

- [ ] **Step 2: Run to see them fail**

Run: `uv run --with behave behave features/ticket_web.feature`
Expected: the new scenarios fail with 404.

- [ ] **Step 3: Implement the ticket page**

- Route match: `<name>` must be a configured project; `<id>` must be a key of `snapshot.tickets` with `parsed=True`. Otherwise 404. Never join URL text into a path.
- Meta line: status, type, priority, assignee, tags, created.
- Relations as in the hook table; each link goes to `/p/<name>/<id>` and shows id, title and status.
- Text blocks in `<pre data-section="...">`; CSS `white-space: pre-wrap`. Empty sections are omitted. Unknown sections use `data-section="other"` with their heading above.

- [ ] **Step 4: Run to see them pass**

Run: `uv run --with behave behave features/ticket_web.feature`
Expected: all scenarios pass.

- [ ] **Step 5: Commit**

```bash
git add plugins/ticket-web features/ticket_web.feature features/steps/web_steps.py
git commit -m "feat: ticket-web ticket page with relations"
```

---

### Task 4: Editing

**Files:**
- Modify: `plugins/ticket-web`, `features/ticket_web.feature`

**Interfaces:**
- Consumes: `Store.get`, `Store.lock`, `Store.refresh`, `run_tk`, `parse_ticket`, `Ticket`.
- Produces: `edit_hash`, `replace_sections`, routes `GET` and `POST /p/<name>/<id>/edit`.

- [ ] **Step 1: Write the failing scenarios**

Fixture ticket `alpha/a-0001`, written with `has content:`:

```
---
id: a-0001
status: open
deps: []
links: []
created: 2026-01-01T00:00:00Z
type: task
priority: 2
---
# First

Old description.

## Design

Old design.

## Notes

**2026-01-02T00:00:00Z**

A note.
```

| Scenario | Submit | Assertions |
|---|---|---|
| Form shows current text | open the form | form fields equal `First`, `Old description.`, `Old design.`, empty acceptance; `base` is 64 hex characters |
| Description edit, exact file | `description` = `New description.` | status 303; `Location` = `/p/alpha/a-0001`; file equals the fixture with only that line changed (use `file should be:`) |
| Title edit | `title` = `Renamed` | 303; file contains `# Renamed` and `Edited: title`; front matter unchanged |
| Title starting with a dash | `title` = `-x fix` | 303; file contains `# -x fix` |
| New section in order | `acceptance` = `It works.` | 303; in the file `## Acceptance Criteria` comes after `Old design.` and before `## Notes`; front matter and notes unchanged |
| Emptied section | `design` = empty | 303; file does not contain `## Design`; front matter and notes unchanged |
| Multi-line and CRLF | `description` = `Line one\r\nLine two` | file contains `Line one\nLine two`, no `\r` |
| Nothing changed | submit untouched | 303; file unchanged |
| Conflict | replace `Old description.` by `Agent text.` on disk after opening; submit `description` = `Mine.` | 409; file contains `Agent text.` and not `Mine.`; response contains `the ticket changed on disk`, `Mine.` and, in `pre.disk[data-field=description]`, `Agent text.` |
| Save after conflict | after the 409, re-read the form from the response and submit again | 303; file contains `Mine.` |
| Foreign note does not block | append a note on disk after opening; submit `description` = `Mine.` | 303; file contains `Mine.` and the appended note |
| Front-matter marker rejected | `description` = `a\n---\nb` | 400; file unchanged; response contains the submitted text |
| Section heading rejected | `design` = `x\n## Extra` | 400; file unchanged |
| Hash line accepted | `design` = `# install deps\nmake` | 303; file contains `# install deps` |
| Empty title rejected | `title` = empty | 400; file unchanged |
| Foreign Origin rejected | submit with header `Origin: http://evil.example` | 403; file unchanged |
| Same Origin accepted | submit with header `Origin: http://127.0.0.1:<port>` (step substitutes the port) | 303 |
| Review Focus 1 | `title` = `Починить поиск`, `description` = `Описание по-русски` | 303; file contains both; GET of the ticket page contains both |
| Review Focus 4 | delete the file after opening the form; submit | 404, not 500; a later GET `/` is 200 |
| Unparsable ticket has no form | GET `/p/alpha/bad-0001/edit` for a file without front matter | 404 |

For "Save after conflict" add the step `When I take the form from the response` (re-parse `context.web_body` into `context.web_form`).

- [ ] **Step 2: Run to see them fail**

Run: `uv run --with behave behave features/ticket_web.feature`
Expected: the new scenarios fail with 404 on `/edit`.

- [ ] **Step 3: Implement `edit_hash` and `replace_sections`**

- Normal form of a value: CRLF and CR to LF, then strip leading and trailing blank lines (the title: strip blanks).
- `edit_hash` = SHA-256 hex of the four normal forms joined with `\0`.
- `replace_sections(text, description, design, acceptance)`: `None` means "leave as is". Work on lines; never re-serialise the file.
  - Split the body after the title line into chunks at each line starting with `## `. Chunk 0 is the description.
  - A changed section: replace its chunk with `[heading line], '', <text lines>, ''` (description: `'', <text lines>, ''`). Empty description: a single `''`.
  - Emptied `Design` / `Acceptance Criteria`: drop the chunk.
  - New `Design`: insert right after the description chunk. New `Acceptance Criteria`: insert after `Design` when present, else after the description.
  - Untouched chunks, the front matter and the title line are copied without change.
  - The result ends with exactly one `\n`.

The "exact file" scenario pins this layout.

- [ ] **Step 4: Implement the form and the save**

- `GET .../edit`: 404 unless the ticket exists and is parsed. Emit `<textarea name="...">` followed by a line break and then the escaped text (HTML drops one leading line break).
- `POST`: follow the spec section "Editing", steps 1-5, inside `with store.lock(name)`:
  - `Origin` present and not `http://127.0.0.1:<port>` or `http://localhost:<port>` -> 403.
  - Read the body with `Content-Length`, decode `application/x-www-form-urlencoded` as UTF-8 (`urllib.parse.parse_qs`, `keep_blank_values=True`).
  - Re-read the file from disk (not from the snapshot). Missing file or unparsable -> 404.
  - Hash mismatch -> 409 with the conflict form: the submitted text in the fields, a new `base` from the disk values, and a `pre.disk` with the disk text under every field whose disk value differs from the submitted value.
  - Validate only the fields whose submitted value differs from the disk value -> 400 with the submitted text and a `p.msg` naming the field and the rule.
  - Title changed -> `run_tk(project, 'set', id, 'title', '--', new_title)`. Non-zero exit -> 400 with its stderr in `p.msg`.
  - A text field changed -> read the file again, `replace_sections`, write `<dir>/.<id>.md.tmp`, `os.replace`.
  - `store.refresh(name)`, then 303 to `/p/<name>/<id>`.

- [ ] **Step 5: Run to see them pass**

Run: `uv run --with behave behave features/ticket_web.feature`
Expected: all scenarios pass.

- [ ] **Step 6: Verify that core commands still read an edited ticket**

Add one scenario: after a description and design edit, `tk show a-0001` (run with the existing step in `<test_dir>/alpha`; add the step `When I run "ticket ..." in web project "NAME"`) succeeds and contains the new text, and `ticket lint` in that project exits 0.

Run: `uv run --with behave behave features/ticket_web.feature`
Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add plugins/ticket-web features/ticket_web.feature features/steps/web_steps.py
git commit -m "feat: ticket-web edit of title and text with conflict detection"
```

---

### Task 5: Live refresh, search, styling

**Files:**
- Modify: `plugins/ticket-web`, `features/ticket_web.feature`, `features/steps/web_steps.py`

**Interfaces:**
- Consumes: `Store.refresh`, the handler, `page`.
- Produces: `Store.watch`, `Store.wait_change`, route `GET /events`, the embedded `CSS` and `JS` strings.

- [ ] **Step 1: Write the failing scenarios**

New steps:
- `When I listen to "/events"`: open a streaming GET in a thread that appends received lines to `context.web_events`; wait until the first line arrives.
- `Then an event should arrive within N seconds`: wait for a line starting with `data:`.
- `When I stop listening`: close the connection.

| Scenario | Assertions |
|---|---|
| Stream opens | GET `/events` answers 200 with `Content-Type: text/event-stream`; the first line is a comment (`:`) |
| A change raises an event | listen; replace a title on disk; an event arrives within 5 seconds; its `data:` is the project name |
| No event without a change | listen; within 2 seconds no `data:` line arrives |
| Review Focus 5 | listen; stop listening; replace a title on disk; `GET "/" should eventually contain` the new title; a second listen still receives events |
| Pages carry the script | `/`, `/?flat=1`, `/p/alpha`, `/p/alpha/a-0001` contain `EventSource`; `/p/alpha/a-0001/edit` does not |
| Search box | `/` contains `id="q"` outside `<main>`; every card has a `data-search` attribute holding project, id, title and tags in lower case |

- [ ] **Step 2: Run to see them fail**

Run: `uv run --with behave behave features/ticket_web.feature`
Expected: the new scenarios fail with 404 on `/events`.

- [ ] **Step 3: Implement the watcher and `/events`**

- `Store`: a `threading.Condition` and an integer `version`; `last_changed` holds the project name. `watch()` runs in a daemon thread started in `main`: every second call `refresh` for each project; on `True` set `last_changed`, increment `version`, `notify_all`. `refresh` called from a request also bumps the version when it rebuilds.
- `GET /events`: headers `Content-Type: text/event-stream`, `Cache-Control: no-store`; write `: ok\n\n` and flush. Loop: `wait_change(seen, 15)`; on a new version write `data: <project>\n\n`; on timeout write `: ping\n\n`. Leave the loop on `BrokenPipeError`, `ConnectionResetError` or `OSError`.

- [ ] **Step 4: Implement the page script and the styles**

`JS` (embedded, about 30 lines), included on every page except the edit form:
- `EventSource('/events')`; on `message`: `fetch(location.href)`, parse with `DOMParser`, replace `document.querySelector('main').innerHTML` with the new `main`, then apply the filter. Debounce: at most one fetch at a time; a message during a fetch schedules one more.
- Filter: on `input` of `#q`, hide every `.card` whose `data-search` does not include the lower-cased query. Keep the query in `sessionStorage` so it survives navigation.

`CSS` (embedded): lanes as a grid with a name column and four equal columns; cards as blocks with a left border in the project color; `pre` with `white-space: pre-wrap`; `prefers-color-scheme: dark` variant; the page works at 1280 px width without horizontal scroll. The owner will adjust the look later, so keep it plain.

- [ ] **Step 5: Run to see them pass**

Run: `uv run --with behave behave features/ticket_web.feature`
Expected: all scenarios pass.

- [ ] **Step 6: Check the page by hand**

```bash
mkdir -p /tmp/tkweb && printf 'port = 7420\n\n[[project]]\nname = "ticket"\npath = "%s"\n' "$PWD" > /tmp/tkweb/web.toml
./ticket web --config /tmp/tkweb/web.toml
```

Open `http://127.0.0.1:7420/`. Expected: the lane `ticket` with the repository's own tickets in four columns; typing in the search box hides cards; `tk add-note <id> x` in another terminal refreshes the page within two seconds (then remove that note change with `git checkout .tickets/`). Stop with Ctrl-C.

- [ ] **Step 7: Commit**

```bash
git add plugins/ticket-web features/ticket_web.feature features/steps/web_steps.py
git commit -m "feat: ticket-web live refresh, search and styles"
```

---

### Task 6: Documentation and completion

**Files:**
- Modify: `README.md`, `plugins/README.md`, `CHANGELOG.md`

- [ ] **Step 1: Update `README.md`**

- Requirements: add "The `web` plugin requires Python 3.11 or newer."
- Usage block, "Official plugins" part, add:
  ```
    web [--port N] [--config PATH]   Local kanban board over the projects listed in
                             ~/.config/ticket/web.toml (needs Python 3.11+; edits need ticket-set)
  ```
- Plugins section: one sentence on `ticket-web` and add it to the list of files to copy or symlink.
- Agent skill paragraph: no change (the skill does not need `ticket-web`).

- [ ] **Step 2: Update `plugins/README.md`**

Add `## ticket-web`: purpose, invocation, the config example from the spec, the four column rules, what can be edited, the working-tree limit, the safety rules (loopback only, Host and Origin checks), and the note that the package scripts do not ship its Python dependency.

- [ ] **Step 3: Update `CHANGELOG.md`**

Under `[Unreleased]` -> `### Plugins`:
`- ticket-web 1.0.0: New plugin, `tk web [--port N] [--config PATH]` serves a local kanban board (Blocked, Ready, In progress, Closed) over the projects listed in `~/.config/ticket/web.toml`, with a ticket page and an edit form for title, description, Design and Acceptance Criteria`

- [ ] **Step 4: Run the whole suite**

Run: `make test`
Expected: 0 failed scenarios, including every older feature file.

Run: `git status --short pkg/ scripts/ ticket`
Expected: no output.

- [ ] **Step 5: Commit the documentation**

```bash
git add README.md plugins/README.md CHANGELOG.md
git commit -m "docs: document ticket-web"
```

- [ ] **Step 6: Report "ready to close" and ask**

Follow the Closing section of the `managing-tk-tickets` skill: check each acceptance criterion of `tic-rceq` against the scenarios, show `tk impact tic-rceq`, and ask the user. Close only after an explicit yes, with `tk close tic-rceq --reason done -m "<what was delivered>"`, then `tk lint --conventions`, `git add .tickets/` and commit.
