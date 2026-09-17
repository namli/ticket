---
name: managing-tk-tickets
description: Use when a project has a `.tickets/` directory or uses the `tk` CLI and a ticket is about to be created, edited, linked, started, closed or reopened, when deferred follow-up work must be recorded, when choosing what to work on next, or before a git commit that may complete a ticket.
---

# Managing tk tickets

Tickets are markdown files in `.tickets/`, committed with the code (not tracked by git -> skip the git parts). Guard plugins enforce the mechanics; this skill covers what no command can decide: how tickets relate, and when one is really done.

**Never rely on remembering the backlog - search it. Every status change is a graph change - report its effect.**

## Requires the guard plugins

Run FIRST, before any other `tk` command:
```bash
for c in close dep undep start reopen impact find set lint ls; do tk help | sed -n '/^Plugins/,$p' | grep -q "^  $c " || echo "MISSING: $c"; done
```
Any `MISSING` line -> STOP: change no ticket and tell the user what is missing; the ticket repo's `plugins/` directory goes on PATH (`plugins/README.md`). There is no manual fallback: the built-ins accept cycles, blocked starts and unsafe closes.

**A guard refusal is a finding, not an obstacle.** Report it and resolve its cause. It offers `--force` and `tk super <cmd>`: use neither unless the user, having seen the refusal, names that override.

## Commands

Flags: `tk help`, `tk <plugin> --help`.

| Need | Command |
|---|---|
| Pick work (only from here) | `tk ready` |
| What a close would change | `tk impact <id>` |
| Search title, body, notes (regexes, OR-ed; `--all` adds closed) | `tk find 'ClassName' 'path/to/file'` |
| Hard blocker / soft relation | `tk dep <blocked> <blocker> --reason "<why>"` / `tk link <a> <b>` (three IDs link every pair) |
| Title, priority, type, assignee, tags, parent | `tk set <id> <field> <value>` |
| Check graph and notes | `tk lint --conventions` |

## Creating

```bash
ID=$(tk create "Imperative title" -t bug -p 2 --tags area,topic -d "What and where: path/File.php:line, Class::method" --design "Approach; what stays untouched" --acceptance "Checkable criteria")
```
ONE line, `$` escaped inside double quotes. The description MUST name files and classes - that is what the search finds.

1. SEARCH open tickets for the files, classes and tags the new one touches; `tk show` every hit.
2. CLASSIFY each hit: "can the new ticket be started AND finished before that one is merged?" No -> `tk dep`. Yes but same files or root cause -> `tk link`. Part of it -> `--parent`. Same problem -> no new ticket, `tk add-note` on the existing one. "Better first" is priority, not a dep; depend on the narrowest real blocker, never on an epic.
3. BOTH DIRECTIONS: the new ticket may block existing ones -> `tk dep <existing> <new>`.
4. REPORT each relation with its reason, and whether the ticket is in `tk ready` or `tk blocked`.

## Closing

The close rides in the commit that completes the work - never earlier, never on a branch without the work. On every commit request find the tickets it completes (`tk ls --status=in_progress`, `tk find` the staged paths). No commit requested -> no close, report "ready to close".

1. CHECK every acceptance criterion against evidence. Unmet -> do not close; splitting off the remainder is the user's call.
2. Create follow-up tickets now, so they land in the same commit.
3. STOP AND ASK. Show the evidence, the resolution and the `tk impact <id>` output. Close only after an explicit yes. "It's done, commit it" authorises the commit, NOT the close - hurry does not change this.
4. `tk close <id> --reason done -m "<what was delivered>"` -> report its `Now ready:` line (true on this branch only, until merged); last child closed -> propose closing the parent.
5. `tk lint --conventions`, then `git add .tickets/` LAST and commit with the work. Commit abandoned -> `tk reopen <id> -m "commit abandoned" --in-progress`.

**Won't do / duplicate / superseded** (`--reason wontdo -m "<why>"`, `duplicate|superseded --ref <id>`): a closed blocker counts as resolved whatever the reason, so the close is refused while open tickets depend on this one. Settle each BEFORE closing, asking the user per dependent: not needed -> `tk undep <dependent> <id>`; replaced -> `tk undep` + `tk dep <dependent> <replacement>`; pointless without it -> close it too. Parent: close or detach (`tk set <child> parent none`) every open child first. Ticket-only commit: ask which branch.

**Reopening** a committed close: `tk reopen <id> -m "<reason>"` -> report its `Re-blocked:` line, naming any ticket there that is `in_progress`; commit with the rework.

## Editing

Fields -> `tk set`. Body typo or wording -> edit `.tickets/<id>.md`; status, deps, links and notes go ONLY through `tk`. New facts -> `tk add-note`, not a body rewrite. Anything that changes scope, splits or merges tickets -> read `editing.md` in this directory FIRST.

## Red flags

- "It is obviously done" -> still ask (Closing step 3).
- A refusal answered with `--force` or `tk super` -> fix the cause instead.
- Asking about dependents after a won't-do close -> settle them first.
