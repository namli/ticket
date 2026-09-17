---
id: tic-hxgf
status: open
deps: [tic-5cgv]
links: [tic-gqng]
created: 2026-09-17T13:11:33Z
type: task
priority: 4
assignee: namli
tags: [plugins, lint]
---
# ticket-lint: print the summary after the findings on a terminal

plugins/ticket-lint writes the summary line ("2 errors, 1 warning") from awk END straight to stderr (print ... | "cat 1>&2") while the findings are captured and only printed by the wrapper after sorting. On a terminal, where stdout and stderr interleave, the summary therefore appears ABOVE the findings and scrolls away on long output. Redirected streams are unaffected, and this order is what the design spec docs/superpowers/specs/2026-09-17-ticket-lint-design.md mandates ("awk writes the summary straight to stderr"), so this is a design change, not an implementation defect. Found by the whole-branch review of tic-5cgv (finding M6).

## Design

Let the wrapper print the summary after the sorted findings: awk reports the two counts to the wrapper (for example as a last stdout record with a reserved key that the wrapper strips, or via its exit status plus a counts line), and the wrapper writes "N errors, M warnings" to stderr after the findings. Keep: summary on stderr, nothing printed on a clean run, exit codes unchanged. Update the Output and Architecture sections of the spec.

## Acceptance Criteria

Running `tk lint 2>&1` on a fixture with findings shows the summary as the LAST line (new scenario in features/ticket_lint.feature; a step that captures the combined stream in order may be needed). Clean run still prints nothing on either stream. Existing lint scenarios stay green. plugins/ticket-lint version bump and CHANGELOG.md "### Plugins" entry.


## Notes

**2026-09-17T13:11:34Z**

Blocked by tic-5cgv: plugins/ticket-lint exists only on branch feat/ticket-lint until tic-5cgv is merged; this ticket changes that file
