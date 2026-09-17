---
id: tic-12tn
status: open
deps: []
links: [tic-5lpp]
created: 2026-09-17T16:34:15Z
type: chore
priority: 3
assignee: namli
tags: [plugins, tests]
---
# ticket-impact: cover remaining graph rules and output order with scenarios

Follow-up from the final review of tic-5lpp. plugins/ticket-impact behaves correctly for these cases (verified by hand by two reviewers) but features/ticket_impact.feature has no scenario for them: self-parent target (no child, no last-child); dangling parent (no last-child); transitive dependents are not reported; a dangling ID inside a 'blocked' list; the id-mismatch error 'Error: no ticket with id <id> (file name and id field differ?)' with exit 1; human-mode section order (Open blockers, Open children, Becomes ready, Still blocked by others, last-child line); ID sort order for blocker / child / blocked lines (only 'ready' is asserted today); whitespace-trimmed ID argument.

## Design

Scenarios only, in features/ticket_impact.feature; reuse existing steps in features/steps/ticket_steps.py ('has raw field' for hand-made deps/parent/id values, 'output line N should contain' for order). No plugin change expected; a scenario that fails reveals a bug - fix it in plugins/ticket-impact and bump tk-plugin-version to 1.0.1 with a CHANGELOG line.

## Acceptance Criteria

One scenario per case listed in the description; make test passes; no new step definitions unless a case cannot be expressed otherwise

