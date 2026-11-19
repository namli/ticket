# ticket-web: local kanban board over several tk projects

Ticket: tic-rceq. Date: 2026-11-19.

## Intent

The owner runs `tk` in several projects on two or three personal machines.
Agents change tickets in the background.
The owner wants one browser page that shows the ticket state of every chosen project.
The page answers two questions: "what is ready to take" and "what waits for a blocker".
The owner also wants to fix a ticket title or text from that page.

## Goals

- Show the tickets of every configured project in four columns.
- Show all projects on one screen, one horizontal lane per project.
- Offer a flat view that merges all projects into the same four columns.
- Show one ticket in full: text, relations, notes.
- Edit title, description, `Design` and `Acceptance Criteria` of a ticket.
- Refresh the page when a ticket file changes on disk.
- Install with `git pull`: no new toolchain, no build step, no third-party file.

## Non-goals

- Status changes, drag and drop, `tk start` / `tk close` / `tk reopen`.
- Edits of deps, links, parent, tags, priority, type, assignee, notes.
- Ticket creation.
- Markdown rendering.
- Authentication, remote access, several users.
- A settings page: the owner edits the config file by hand.
- Branch or worktree awareness. The board shows the working tree of the configured path.
  A ticket that an agent closed on another branch stays open on the board until the merge.
- Git operations. An edit stays uncommitted in the project; the owner commits it.

## Anti-goals

- The server writes anything other than the title and the three text sections.
- The server passes `--force` or calls `tk super`.
- The server listens on an address other than `127.0.0.1`.
- The plugin needs a package outside the Python standard library.
- An edit silently overwrites a change that an agent made after the form opened.

## Constraints

- Python 3.11 or newer (`tomllib`). Standard library only.
- One executable file: `plugins/ticket-web`. CSS, JavaScript and HTML live in it as strings.
- The file starts with `#!/usr/bin/env python3`.
  Lines 2-3 hold `# tk-plugin: ...` and `# tk-plugin-version: 1.0.0`.
- No file is added that matches `plugins/ticket-*` except the plugin itself.
  `scripts/publish-homebrew.sh` and `scripts/publish-aur.sh` treat every such file as a plugin.
- The core script `ticket`, `scripts/` and `pkg/` stay untouched. Not added to `pkg/extras.txt`.
- The owner installs by `git pull` and does not run releases on this fork.
  A release would package `ticket-web` without its Python and `ticket-set` dependencies; that is out of scope.
- Title edits need `plugins/ticket-set` on PATH.
- UI text is English: `Blocked`, `Ready`, `In progress`, `Closed`.

## Approaches

| | A. Server HTML + htmx | B. Server HTML + own small JS | C. JSON API + client rendering |
|---|---|---|---|
| Third-party files | `htmx.min.js` | none | none or a framework |
| Auto-refresh | htmx SSE extension | `EventSource`, replace `<main>` | `EventSource`, re-render |
| Edit | `hx-post` form | plain HTML form, POST, redirect | `fetch` plus form code |
| Code size | medium | smallest | largest |

**Picked: B.** The owner dropped drag and drop, so the page mostly reads.
Two interactive parts remain: auto-refresh and search. Each takes about 15 lines of plain JavaScript.
A is right only if card actions come back later. C doubles the code for no gain.

Earlier decisions, kept:

- **Python, not Go or Node.** The machines have Python 3.14 and no Go toolchain.
  A single binary gives nothing to a tool installed by `git pull`.
- **This repository, not a separate one.** Upstream `wedow/ticket` is inactive.
  One `git pull` updates core, plugins, skill and board together.
- **One file, not `plugins/ticket-web` plus a `web/` directory** (builder's call, not discussed with the owner).
  With no vendored library, a `web/` directory holds only one CSS and one JS file.
  One file keeps the plugin installable the same way as every other plugin.

## Invocation

```
tk web [--port N] [--config PATH]
```

- The server runs in the foreground until Ctrl-C.
- The first stdout line is `tk web: http://127.0.0.1:<port>/`. Flush it at once.
- Port order: `--port`, then `port` in the config, then `7420`.
  `--port 0` asks the OS for a free port; the printed line shows the real one. Tests use this.
- A busy port: error on stderr, exit 1.
- The server does not open a browser.
- `tk web` works from any directory. It does not need a `.tickets/` in the current directory.

## Config

Path: `$TK_WEB_CONFIG`, else `~/.config/ticket/web.toml`. `--config` overrides both.

```toml
port = 7420

[[project]]
name = "ticket"
path = "~/www/ticket"

[[project]]
name = "eagle"
path = "/home/me/www/eagle"
color = "#3b82f6"
```

| Key | Rule |
|---|---|
| `name` | Required, unique, matches `[A-Za-z0-9_-]+`. Used in URLs and on cards. |
| `path` | Required. Project root; `~` is expanded. Tickets are in `<path>/.tickets`. |
| `color` | Optional CSS color. Default: a color derived from the name. |

- Lane order is the order in the file.
- The server reads the config once at start. A config change needs a restart.
- Missing or invalid config: stderr names the path and prints the example above, exit 1.
- A project whose `<path>/.tickets` is missing does not stop the server.
  Its lane shows the error text; the other projects render.

## Reading tickets

The server parses `<path>/.tickets/*.md` itself. `tk query` returns no title and no body.

File format (written by `cmd_create`, `ticket` lines 197-231):

```
---
id: tic-o862
status: open
deps: [tic-mwhy, tic-yxrw]
links: [tic-xg2z]
created: 2026-09-17T11:29:13Z
type: feature
priority: 3
assignee: namli
parent: tic-sa3b
tags: [plugins, editing, graph]
---
# Title

Description text.

## Design

...

## Acceptance Criteria

...

## Notes

**2026-09-17T11:29:13Z**

Note text
```

- Front matter: the lines between the first two `---` lines. Flat `key: value`. Lists are `[a, b]`.
- Title: the first line that starts with `# `.
- Description: the text between the title and the first `## ` heading.
- Sections: `## Design`, `## Acceptance Criteria`, `## Notes`.
  Any other `## ` section is kept byte for byte and shown read-only.
- A file that does not parse appears as a card with its file name and the word `unparsable`.

**Blocked state.** The server runs `tk blocked` for each project and takes the first word of each line.
The blocking rule stays in one place, the core script.
Run it as `$TK_SCRIPT blocked`, with `cwd` = project path and `TICKETS_DIR=<path>/.tickets` set explicitly.
`tk` exports the `TICKETS_DIR` of the caller's project to the plugin; an inherited value would point every project at one directory.
If `TK_SCRIPT` is unset (plugin started directly), use `tk` from PATH.
Skip the call when the directory holds no `*.md` file: `tk blocked` exits 2 with empty stderr there. The lane is then empty, not an error.
If the command fails, the lane shows its exit code and stderr.

`tk blocked` alone decides the column. The blockers printed on a card (deps that are not closed) are display only.

Known limit: the core awk code toggles front-matter state on every `---` line, the server reads only the first block.
A hand-written `---` line inside notes can make the two disagree. The server does not handle this case.

**Cache and watch.** One snapshot per project: parsed tickets plus the blocked set.
A watcher thread compares `(name, mtime_ns, size)` of all `*.md` files once a second.
On a difference it rebuilds that project's snapshot and notifies the SSE clients.

## Columns

| Column | Rule |
|---|---|
| Blocked | status `open` and the id is in the blocked set |
| Ready | status `open` and the id is not in the blocked set |
| In progress | status `in_progress`; a ⛔ mark when the id is in the blocked set |
| Closed | status `closed` or `done` (`cmd_closed` treats both as closed, `ticket` line 781) |

- A ticket with any other status goes to `Ready` and shows the raw status as a badge.
- The "open count" of a lane is the number of its tickets outside `Closed`.
- Order in `Blocked`, `Ready`, `In progress`: priority ascending, then id.
- Order in `Closed`: newest first, by the timestamp of the last note; fallback `created`.
  File mtime is useless here: after `git clone` all files share one mtime.

## Pages

| Route | Content |
|---|---|
| `GET /` | All projects as lanes. Each lane: name, open count, four columns. `Closed` shows the 5 newest and a `N more` link to the project page. |
| `GET /?flat=1` | The same four columns without lanes. Every card carries the project name and color. `Closed` shows the 5 newest per project. |
| `GET /p/<name>` | One project, full width. `Closed` shows 50; `?closed=all` shows all. |
| `GET /p/<name>/<id>` | One ticket in full, with an `Edit` link. |
| `GET /p/<name>/<id>/edit` | Edit form. |
| `POST /p/<name>/<id>/edit` | Save. |
| `GET /events` | SSE stream. |

Sketch of `/`:

```
            BLOCKED        READY           IN PROGRESS     CLOSED
ticket      tic-o862 P3    tic-8qs0 P2     tic-rceq P2     tic-xg2z
 9 open      ⛔ tic-yxrw   tic-seki P2                     tic-x75b   8 more
──────────────────────────────────────────────────────────────────────────
eagle       eag-a1b2 P1    eag-77fe P0     eag-c3d4 P2     eag-9911
 14 open                   eag-1c0a P2                     31 more
```

**Card:** id, title, priority, type, tags, open blockers (deps that are not closed or do not exist), parent id.
An epic is an ordinary card with the type badge `epic`. The card links to the ticket page.
The card key is project + id: id prefixes of two projects can collide.

**Ticket page:** title; status, type, priority, assignee, tags, created; parent, children (tickets whose `parent` is this id), deps with their status, dependents, links — each a link to that ticket; then description, `Design`, `Acceptance Criteria`, other sections, notes.
Text is shown as written, HTML-escaped, with `white-space: pre-wrap`.

**Header on every page:** links to `/`, flat view, each project; a search box.

**Search.** One text box. JavaScript hides the cards whose text (project, id, title, tags) does not contain the query, case-insensitive. No server request.

**Auto-refresh.** Board pages open `EventSource('/events')`.
On an event the script fetches the current URL, replaces the content of `<main>` and applies the search filter again.
The search box sits outside `<main>`, so its value survives.
The ticket page refreshes the same way. The edit form page does not refresh.
The server sends a comment line every 15 seconds to keep the connection alive.

## Editing

Form fields: title (one line), description, `Design`, `Acceptance Criteria` (text areas), and a hidden `base`.
`base` = SHA-256 over the four editable values as they were on disk when the form was rendered.
The hash does not cover front matter or notes: an agent that adds a note or changes the status does not block the save.

A field is "changed" when the submitted value differs from the value on disk after CRLF-to-LF conversion.

Save steps, under one lock per project:

1. Read the file and compute the hash of its four editable values. If it differs from `base`: respond 409, write nothing.
   Show the form again with:
   - the submitted text in the fields;
   - the message "the ticket changed on disk - compare and save again";
   - under each field whose disk value changed, the current disk text, read-only;
   - a new `base` computed from the current disk values.
   The owner sees the foreign change before the second save can replace it.
2. Validate the changed fields only. Reject with 400 and the same form when:
   - the title is empty or has a line break;
   - a changed text has a line that is exactly `---`, or a line that starts with `## `.
     The core awk code toggles front-matter state on every `---` line (`ticket` line 769), and a `## ` line would start a new section.
     A line that starts with `# ` is allowed: the core reads only the first `# ` line as the title.
   An unchanged field is never validated, so a ticket that already holds such a line stays editable.
3. If the title changed: run `$TK_SCRIPT set <id> title -- <new title>` (same `cwd` and `TICKETS_DIR` as above).
   The `--` keeps a title that starts with `-` from being read as an option (`plugins/ticket-set` line 45).
   `plugins/ticket-set` validates the value and appends the `Edited:` note.
   On a non-zero exit: show its stderr verbatim, write nothing else.
4. If a text section changed: read the file again, replace only those sections, write it.
   - Front matter, title line, `## Notes` and unknown sections stay byte for byte.
   - Convert CRLF to LF. Strip trailing blank lines of each section.
   - An emptied `Design` or `Acceptance Criteria` loses its heading.
   - A new section goes in the order: description, `Design`, `Acceptance Criteria`, then the rest.
   - Write to a temp file in the same directory, then `os.replace`. The temp name must not end in `.md`.
   - Body edits write no note: the skill treats them as wording fixes.
5. Respond 303 to the ticket page.

Nothing changed: skip steps 3-4, respond 303.

## Safety

- Bind `127.0.0.1` only.
- Reject a request whose `Host` header is not `127.0.0.1:<port>` or `localhost:<port>` (DNS rebinding).
- Reject a POST whose `Origin` header is present and does not match the same two hosts (cross-site form post).
- `<name>` must be a configured project. `<id>` must be the id of a parsed ticket of that project.
  The server never builds a file path from URL text.
- Escape every ticket and config value in HTML.
- Call `tk` with an argument list, never through a shell.

## Tests

`features/ticket_web.feature`, steps in a new file `features/steps/web_steps.py`.

New steps: create several project directories with tickets; write a config; start `tk web --port 0` in the background and read the port from the first stdout line; GET and POST with `urllib`; stop the server in `after_scenario` (`features/environment.py`).

Scenarios:

- `/`, `/?flat=1`, `/p/<name>` return 200; each ticket sits in the right column (open, blocked, in progress, blocked in progress, closed).
- A card of the flat view names its project.
- Two projects with the same ticket id both render and link to different pages.
- `Closed` on `/` shows 5 tickets and the `N more` link; order follows the last note timestamp.
- The ticket page shows text, deps, dependents, children and notes.
- Missing config: exit 1, stderr names the path and shows the example.
- A project path without `.tickets`: its lane shows an error, the other project renders.
- Edit of the title: the heading changes and the `Edited:` note exists.
- Edit of description, `Design`, `Acceptance Criteria`: the file changes; front matter and notes are byte-identical.
- Emptied `Design` loses its heading; a filled new section appears in order.
- Stale `base` (description changed on disk): 409, file unchanged, the page shows the disk text; a second save with the new `base` succeeds.
- A note added on disk after the form opened: the save succeeds and the note survives.
- Changed text with a `---` line or a `## ` line: 400, file unchanged. A `# ` line is accepted.
- A title that starts with `-` saves.
- A project with an empty `.tickets/` renders an empty lane.
- Unknown project, unknown id: 404.
- Wrong `Host` header: rejected. POST with a foreign `Origin`: rejected.
- A ticket file changed on disk: a new GET shows the change without a restart, and `/events` delivers an event.
- `tk help` lists `web`.

## Documentation

- `README.md`: `web` in the "Official plugins" part of the usage block; a sentence in the Plugins section; Python 3.11 in Requirements.
- `plugins/README.md`: a `ticket-web` section with the config example.
- `CHANGELOG.md`: `### Plugins` — `ticket-web 1.0.0`.
- Ticket tic-rceq: its text still describes htmx, SortableJS, status writes and a `web/` directory. Update it to this design before implementation.

## Left to the builder

- Visual design: layout details, colors, dark mode. The owner will adjust the look on the running page.
- Function and class structure inside `plugins/ticket-web`.
- Wording of error pages.
- How SSE clients are tracked and woken (condition variable, queue).
