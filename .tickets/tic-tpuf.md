---
id: tic-tpuf
status: closed
deps: []
links: [tic-xj6g]
created: 2026-09-17T14:40:57Z
type: feature
priority: 3
assignee: namli
tags: [core, listing]
---
# Show ticket type in tk ready output

cmd_ready in ticket (ticket:653) prints 'id [Pn][status] - title'. Add the ticket type so work can be picked by kind: 'id [Pn][status][type] - title'. Ported from an uncommitted local patch in the install clone ~/.local/opt/ticket. Files: ticket (cmd_ready awk), features/ticket_listing.feature, README.md, CHANGELOG.md.

## Design

Parse 'type:' in the cmd_ready awk front-matter pass, store per id, default to 'task' when missing, add as a field before the title in the output record. cmd_blocked, cmd_closed and plugins/ticket-ls stay untouched.

## Acceptance Criteria

tk ready prints [type] after [status]; ticket without type shows [task]; features/ticket_listing.feature covers task and a non-task type; make test passes; CHANGELOG.md updated


## Notes

**2026-09-17T14:43:46Z**

Closed: done - tk ready prints [type] after [status], defaults to task
