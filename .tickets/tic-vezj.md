---
id: tic-vezj
status: closed
deps: []
links: [tic-xj6g]
created: 2026-09-17T11:29:13Z
type: feature
priority: 2
assignee: namli
parent: tic-sa3b
tags: [plugins, search]
---
# Add ticket-find plugin: search ticket content, open tickets by default

New plugin plugins/ticket-find, used as `tk find <pattern>`. plugins/ticket-query returns front matter only, so SKILL.md tells the agent to run `grep -L "^status: closed" .tickets/*.md | xargs -r grep -il ...` before every create. Replace that pipeline with one command that prints normal list lines.

## Design

Case-insensitive extended regex over title, body and notes of non-closed tickets; -a/--all includes closed; several patterns are OR-ed; -T <tag> narrows by tag like plugins/ticket-ls. Output format identical to plugins/ticket-ls (`id [Pn][status] - title`) so it chains with other commands; exit 1 when nothing matches. Use rg when available like _grep in `ticket`.

## Acceptance Criteria

Scenarios in features/ticket_find.feature: match in body; match in notes; closed excluded by default and included with --all; multiple patterns; tag filter; no match exits 1. SKILL.md quick reference uses `tk find`. Behave scenarios added and `make test` passes; README.md usage block, plugins/README.md and CHANGELOG.md (### Plugins, version 1.0.0) updated; plugin has tk-plugin and tk-plugin-version metadata; NOT added to pkg/extras.txt (new plugin, not a core extraction).


## Notes

**2026-09-17T13:11:34Z**

Related tic-xj6g: do not copy gsub(/[\[\] ]/...) from plugins/ticket-ls into ticket-find; use /[][]/ as plugins/ticket-lint does.

**2026-09-17T15:36:42Z**

Design decisions confirmed by namli on 2026-09-17, deviating from the Design section: (1) output is 'id [Pn][status] - title' as written here - plugins/ticket-ls actually prints 'id [status] - title <- [deps]'; (2) only --all, no -a short form: -a means assignee in ls/ready/blocked/closed; (3) awk-only matching, no rg/_grep prefilter: front matter must be excluded from the search, which needs awk anyway, and rg/awk regex dialects differ. Exit codes: 0 match, 1 no match, 2 usage error / invalid regex / no .tickets.

**2026-09-17T15:39:15Z**

Closed: done - plugins/ticket-find 1.0.0 (tk find [--all] [-T tag] <pattern>...), 20 scenarios in features/ticket_find.feature, make test 180/180 green; README.md, plugins/README.md, CHANGELOG.md and SKILL.md updated; not in pkg/extras.txt
