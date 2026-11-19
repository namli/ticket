---
id: tic-rceq
status: open
deps: []
links: []
created: 2026-11-19T15:34:27Z
type: feature
priority: 2
assignee: namli
tags: [plugins, web]
---
# Add ticket-web plugin: local kanban board over several tk projects

New plugin plugins/ticket-web, used as `tk web`: a local HTTP server that shows kanban columns (open, in_progress, closed) for every tk project listed in a per-machine config file, plus a combined board. Stack: Python 3.11+, one file, standard library only (http.server.ThreadingHTTPServer, tomllib, subprocess), no build step; the client is htmx + SortableJS, vendored under web/static/. Go was rejected: no Go toolchain on the machines, and a single binary gives nothing to a tool installed by git pull with plugins/ on PATH. The plugin lives in this repository so that one git pull updates core, plugins, skill and board on every machine.

## Design

Files: plugins/ticket-web (executable, #!/usr/bin/env python3, tk-plugin and tk-plugin-version comments in the first 10 lines), web/static/htmx.min.js, web/static/sortable.min.js, web/static/board.css, web/templates/ (only if the HTML does not fit in the server file), web/web.example.toml, features/ticket_web.feature. The plugin finds web/ through os.path.realpath(__file__), so a symlink on PATH works. Config: ~/.config/ticket/web.toml, path overridden by TK_WEB_CONFIG; keys: port, and [[project]] with name, path, optional color. Projects are listed by hand, no auto-discovery; the config is not committed, only the example is. Reads: plugins/ticket-query returns front matter only, no title, so the server parses .tickets/*.md of each project itself (front matter + first "# " heading); ids for the ready state come from `tk ready` run in the project directory. Cache per project, invalidated by polling file mtimes once a second; a change sends an SSE event and htmx swaps the columns. Writes: only through tk with cwd = project path: `tk start <id>`, `tk close <id> --reason <r> -m <text>`, `tk reopen <id> -m <text>`. The UI asks for the close reason and the reopen text in a dialog. A guard refusal is shown to the user verbatim; the server never passes --force and never calls `tk super`. Routes: / combined board (ready and in_progress tickets of all projects, each card carries the project name and color), /p/<name> board of one project, /all every project with its own columns. Card key is project + id (id prefixes can collide). Closed column limited to the last N tickets. Filters by tag, assignee, priority live in the URL query. Dragging a card between projects is not allowed. The server binds 127.0.0.1 only. Untouched: core script `ticket`, scripts/publish-homebrew.sh, scripts/publish-aur.sh, pkg/ (they install a plugin as one file, so web/ would not ship; installation is git pull + PATH).

## Acceptance Criteria

Scenarios in features/ticket_web.feature: with a config of two projects GET /, /p/<name> and /all return 200 and show each ticket in the column of its status; / shows only ready and in_progress tickets and names the project on each card; a missing config gives an error that names the expected path and web/web.example.toml; a project path without .tickets is reported and the other projects still render; POST start on a ticket with an open blocker returns the refusal text of plugins/ticket-start and the status stays open; close without a reason is rejected; reopen writes the Reopened: note; a ticket file changed on disk shows up without a server restart; the server listens on 127.0.0.1 only. `tk help` lists web. `make test` passes. README.md usage block, plugins/README.md and CHANGELOG.md (### Plugins, ticket-web 1.0.0) updated; NOT added to pkg/extras.txt (new plugin, not a core extraction).

