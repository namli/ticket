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
# Add redep and merge plugins for splitting and merging tickets

Deferred, lowest value: splits and merges are rare and mostly judgment. Plugins plugins/ticket-redep (`tk redep <dependent> <old> <new> --reason <text>`: undep old + dep new + both notes in one step) and plugins/ticket-merge (`tk merge <dup> <keep>`: copy a summary note, re-point dependents of dup to keep, close dup as `Closed: duplicate of <keep>`). Automates the Splitting and Merging duplicates paragraphs of skills/managing-tk-tickets/editing.md.

## Design

Build on the guarded dep/undep and guarded close plugins rather than editing front matter directly, so cycle checks and note prefixes come for free.

## Acceptance Criteria

Scenarios in features/ticket_redep.feature and features/ticket_merge.feature: dependents re-pointed, notes written on every touched ticket, cycle through the new target rejected, dup closed with the duplicate prefix. Behave scenarios added and `make test` passes; README.md usage block, plugins/README.md and CHANGELOG.md (### Plugins, version 1.0.0) updated; plugin has tk-plugin and tk-plugin-version metadata; NOT added to pkg/extras.txt (new plugin, not a core extraction).


## Notes

**2026-09-17T11:29:13Z**

Blocked by tic-mwhy: redep is built on the guarded dep/undep (cycle check and note prefixes)

**2026-09-17T11:29:13Z**

Blocked by tic-yxrw: merge closes the duplicate through the guarded close with --reason duplicate
