---
id: tic-vezj
status: open
deps: []
links: []
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

