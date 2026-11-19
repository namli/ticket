---
id: tic-rceq
status: in_progress
deps: []
links: []
created: 2026-11-19T15:34:27Z
type: feature
priority: 2
assignee: namli
tags: [plugins, web]
---
# Add ticket-web plugin: local kanban board over several tk projects

New plugin plugins/ticket-web, used as `tk web`: a local HTTP server that shows the tickets of every tk project listed in a per-machine config file, in four columns (Blocked, Ready, In progress, Closed), and lets the owner edit the title and text of a ticket. The board does not change status, deps or links. Stack: Python 3.11+, one file, standard library only (http.server.ThreadingHTTPServer, tomllib, subprocess), no build step, no third-party file; CSS and JavaScript live in the plugin file as strings. Go was rejected: no Go toolchain on the machines, and a single binary gives nothing to a tool installed by git pull with plugins/ on PATH. The plugin lives in this repository so that one git pull updates core, plugins, skill and board on every machine. Full design: docs/superpowers/specs/2026-11-19-ticket-web-design.md.

## Design

Files: plugins/ticket-web (executable, #!/usr/bin/env python3, tk-plugin and tk-plugin-version comments in the first 10 lines), features/ticket_web.feature, features/steps/web_steps.py. No web/ directory and no other plugins/ticket-* file: scripts/publish-homebrew.sh and scripts/publish-aur.sh treat every such file as a plugin. Invocation: `tk web [--port N] [--config PATH]`, foreground, first stdout line `tk web: http://127.0.0.1:<port>/`, --port 0 picks a free port. Config: ~/.config/ticket/web.toml, path overridden by TK_WEB_CONFIG or --config; keys: port, and [[project]] with name, path, optional color. Projects are listed by hand, no auto-discovery; the server reads the config once at start. Reads: plugins/ticket-query returns front matter only, so the server parses .tickets/*.md of each project itself (front matter, first "# " heading, description, Design, Acceptance Criteria, Notes). The blocked set comes from `tk blocked`, run with cwd = project path and TICKETS_DIR set explicitly. Cache per project, rebuilt when a poll of file name, mtime and size (once a second) finds a difference; a change sends an SSE event and the page script replaces the content of <main>. Columns: Blocked = open and in the blocked set; Ready = open and not in it; In progress = in_progress (mark when blocked); Closed = closed or done, newest first by last note timestamp. Routes: / all projects as lanes, /?flat=1 the same columns without lanes with the project name on each card, /p/<name> one project, /p/<name>/<id> one ticket, /p/<name>/<id>/edit form and save, /events SSE. Card key is project + id (id prefixes can collide). Search is one text box that hides cards on the client. Editing: title goes through `tk set <id> title -- <value>` (plugins/ticket-set writes the Edited: note); description, Design and Acceptance Criteria are replaced in the file by the server, front matter and notes stay byte for byte, write is temp file + os.replace. A hidden hash of the four editable values detects a concurrent change: 409, nothing written, the form shows the disk text next to the submitted text. A changed text with a `---` line or a line starting with `## ` is rejected. Safety: bind 127.0.0.1 only, check the Host header and the Origin of a POST, never build a file path from URL text, escape all values, call tk with an argument list. The server never passes --force and never calls `tk super`. Untouched: core script `ticket`, scripts/, pkg/.

## Acceptance Criteria

Scenarios in features/ticket_web.feature: with a config of two projects GET /, /?flat=1 and /p/<name> return 200 and show each ticket in the right column (open, blocked, in progress, blocked in progress, closed); a card of the flat view names its project; two projects with the same ticket id both render and link to different pages; Closed on / shows 5 tickets and the "N more" link in last-note order; the ticket page shows text, deps, dependents, children and notes; a missing config exits 1 and stderr names the path and shows the example; a project path without .tickets shows an error in its lane and the other project renders; a project with an empty .tickets renders an empty lane; a title edit changes the heading and writes the Edited: note; a title that starts with "-" saves; an edit of description, Design and Acceptance Criteria changes the file and leaves front matter and notes byte-identical; an emptied Design loses its heading and a filled new section appears in order; a stale hash gives 409 with the file unchanged and the disk text on the page, and a second save succeeds; a note added on disk after the form opened does not block the save; a changed text with a `---` or `## ` line gives 400 with the file unchanged, a `# ` line is accepted; unknown project or id gives 404; a wrong Host header and a POST with a foreign Origin are rejected; a ticket file changed on disk shows up without a restart and /events delivers an event. `tk help` lists web. `make test` passes. README.md (usage block, Plugins section, Python 3.11 in Requirements), plugins/README.md (ticket-web section with the config example) and CHANGELOG.md (### Plugins, ticket-web 1.0.0) updated; NOT added to pkg/extras.txt (new plugin, not a core extraction).


## Notes

**2026-11-19T16:10:44Z**

Edited: scope narrowed after the design discussion with the owner (docs/superpowers/specs/2026-11-19-ticket-web-design.md). Removed: drag and drop, status writes (tk start/close/reopen), htmx, SortableJS, the web/ directory, the /all route, filters by assignee and priority. Added: four columns with Blocked split from Ready, lanes per project, ticket page, edit of title and text with conflict detection. Body rewritten to match.
