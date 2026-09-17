---
id: tic-vsgg
status: open
deps: []
links: [tic-x75b]
created: 2026-09-17T20:23:14Z
type: task
priority: 3
assignee: namli
tags: [skill, docs]
---
# Tell the skill what to do with an authorised commit while the close waits for a yes

skills/managing-tk-tickets/SKILL.md, Closing: 'It is done, commit it' authorises the commit but not the close, and the close must ride in the commit that completes the work. The skill does not say what happens to the commit while the agent waits for the yes. Observed in the tic-x75b close-under-pressure scenario: the old skill committed the work at once and offered a ticket-only close commit afterwards, the new skill held the commit until the answer. Both follow the text, the behaviour is not determined.

## Design

Pick one rule and state it in Closing step 3, keyed to an observable condition (e.g. user blocked or hurry stated -> commit the work now, the close follows as an amend if unpushed, else as a ticket-only commit; otherwise hold the commit and ask). Decide the rule with namli first. Keep it to one or two sentences; no new section.

## Acceptance Criteria

Closing names the rule; re-tested per superpowers:writing-skills on the close-under-pressure scenario with 3+ runs that converge on the same behaviour; SKILL.md word count does not grow by more than 40 words.

