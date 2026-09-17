---
id: tic-xg2z
status: closed
deps: []
links: [tic-o862]
created: 2026-09-17T11:29:13Z
type: feature
priority: 2
assignee: namli
parent: tic-sa3b
tags: [plugins, editing]
---
# Add ticket-set plugin: change title, priority, type, tags, parent, assignee without an editor

New plugin plugins/ticket-set, used as `tk set <id> <field> <value>`. No command changes these fields and plugins/ticket-edit needs a terminal, so SKILL.md sends agents to hand-edit .tickets/<id>.md, which risks broken front matter.

## Design

Fields: title (rewrites the first `# ` heading), priority (0-4 validated), type (bug|feature|task|epic|chore validated), assignee, tags (comma list written as `[a, b]`; +tag / -tag to add or remove), parent (resolved via partial ID, must exist, must not be the ticket itself or its descendant; `none` removes it). Refuse status, deps, links, id, created: those go through their own commands. Same sed approach as update_yaml_field (ticket:142), escaping `/` and `&` in values. Appends note `Edited: <field> <old> -> <new>` unless --no-note.

## Acceptance Criteria

Scenarios in features/ticket_set.feature: each field changes and `tk show` reflects it; invalid priority/type rejected; parent self/descendant rejected; status/deps refused with a hint; value containing / and & survives; note written. Behave scenarios added and `make test` passes; README.md usage block, plugins/README.md and CHANGELOG.md (### Plugins, version 1.0.0) updated; plugin has tk-plugin and tk-plugin-version metadata; NOT added to pkg/extras.txt (new plugin, not a core extraction).


## Notes

**2026-09-17T19:28:54Z**

Design changes agreed with the user: (1) 'none' removes assignee and tags too, not only parent; (2) the write is one awk pass limited to the front matter with the value passed through the environment, instead of the sed approach of update_yaml_field (ticket:142) - that sed rewrites a body line like 'priority: high' and needs / and & escaped. Extra guards found while implementing: multi-line values refused, surrounding blanks trimmed, tags with spaces or brackets refused, plain and signed tags cannot be mixed.

**2026-09-17T19:34:48Z**

Closed: done - plugins/ticket-set 1.0.0 (tk set <id> <field> <value>): title, priority, type, assignee, tags, parent; front-matter-only awk write, Edited: note, 50 scenarios in features/ticket_set.feature, README.md, plugins/README.md and CHANGELOG.md updated
