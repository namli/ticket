---
id: tic-x75b
status: closed
deps: [tic-5lpp, tic-yxrw, tic-6rw0, tic-mwhy, tic-vezj, tic-xg2z, tic-5cgv]
links: [tic-vsgg]
created: 2026-09-17T11:29:13Z
type: task
priority: 2
assignee: namli
parent: tic-sa3b
tags: [skill, docs]
---
# Shrink managing-tk-tickets skill to judgment-only once the plugins exist

Rewrite skills/managing-tk-tickets/SKILL.md and skills/managing-tk-tickets/editing.md (and the installed copy in ~/.claude/skills/managing-tk-tickets) around the new commands: impact, guarded close/start/reopen/dep/undep, find, set, lint. Remove every instruction that a plugin now enforces ("tk facts that bite", manual note prefixes, grep pipeline, "edit the file directly", manual VERIFY). Keep: classification dep vs link vs parent vs note, both-directions check, STOP AND ASK before close, close rides in the completing commit, stage .tickets/ last, scope-change rules.

## Design

Add an install note: the skill requires the plugins on PATH; state the fallback (old manual rules) or fail loudly if `tk impact` is missing. Update the README.md "Agent skill" subsection accordingly.

## Acceptance Criteria

SKILL.md is materially shorter (target about half); no rule duplicates a plugin guard; every command named in the skill exists in `tk help`; skill re-tested per superpowers:writing-skills on create, close, wont-do close and reopen scenarios.


## Notes

**2026-09-17T11:29:13Z**

Blocked by tic-5lpp: the skill can only drop a manual rule once the command that enforces it exists

**2026-09-17T11:29:13Z**

Blocked by tic-yxrw: the skill can only drop a manual rule once the command that enforces it exists

**2026-09-17T11:29:13Z**

Blocked by tic-6rw0: the skill can only drop a manual rule once the command that enforces it exists

**2026-09-17T11:29:13Z**

Blocked by tic-mwhy: the skill can only drop a manual rule once the command that enforces it exists

**2026-09-17T11:29:13Z**

Blocked by tic-vezj: the skill can only drop a manual rule once the command that enforces it exists

**2026-09-17T11:29:13Z**

Blocked by tic-xg2z: the skill can only drop a manual rule once the command that enforces it exists

**2026-09-17T11:29:13Z**

Blocked by tic-5cgv: the skill can only drop a manual rule once the command that enforces it exists

**2026-09-17T20:23:19Z**

Closed: done - SKILL.md 1273 -> 870 words (-32%, not the half targeted), editing.md 400 -> 356; fail-loud plugin check replaces every manual fallback; README Agent skill updated; re-tested on create, close, wont-do, reopen and no-plugins scenarios; follow-up tic-vsgg
