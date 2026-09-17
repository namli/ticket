---
name: managing-tk-tickets
description: Use when a project has a `.tickets/` directory or uses the `tk` CLI and a ticket is about to be created, edited, linked, started, closed or reopened, when deferred follow-up work must be recorded, when choosing what to work on next, or before a git commit that may complete a ticket.
---

# Managing tk tickets

## Overview

`tk` is a minimal tracker: tickets are markdown files in `.tickets/`, committed with the code. It validates almost nothing, so the dependency graph stays true only through these conventions.

**Never rely on remembering the backlog - search it. Every status change is a graph change - report its effect.**

If `.tickets/` is missing, create it with the first `tk create`. If it is not tracked by git, skip the git parts below.

## tk facts that bite

- ANY closed blocker counts as resolved, whatever the reason: a wrong close silently moves dependents to `tk ready`. The built-in close (`tk super close`, `tk status <id> closed`) has no guards (closes blocked tickets and parents with open children, records no reason); the `ticket-close` plugin makes `tk close` guarded - `tk help` lists `close` under Plugins when it is installed.
- `tk reopen` silently re-blocks dependents and sets `open`; restore work in progress with `tk status <id> in_progress`.
- Self-deps and cycles are accepted: run `tk dep cycle` after every dep change. `tk start` works on a blocked ticket - never do it.
- No command changes title / priority / tags / parent / body, and `tk edit` needs a terminal: edit `.tickets/<id>.md` directly. Status, deps, links, notes go ONLY through `tk`.
- `tk query` returns front matter only; search content with `tk find`. `tk show <id>` renders **Blockers**, **Blocking**, **Children**.
- `tk create` prints only the ID. Write it on ONE line: a `# comment` after a `\` ends the command and leaves a junk ticket. In double quotes escape `$`.

## Quick reference

| Need | Command |
|---|---|
| Pick work (only from here) | `tk ready` |
| What waits on what | `tk show <id>`, `tk dep tree <id>`, `tk blocked` |
| Filter | `tk ls --status=in_progress`, `tk ls --tag=x` |
| Hard blocker / soft relation | `tk dep <blocked> <blocker>` / `tk link <a> <b>` |
| History | `tk add-note <id> "text"` (append-only, timestamped) |

Search open tickets (content = `tk find`, tags = `tk query`); patterns are case-insensitive regexes, OR-ed; exit 1 = no hit:
```bash
tk find 'ClassName' 'path/to/file'
tk find -T tag 'ClassName'
tk query '.status != "closed" and (.tags | index("tag"))' | jq -r .id
```
`--all` adds closed tickets. No `tk find` (plugin not installed): `grep -L '^status: closed' .tickets/*.md | xargs -r grep -il 'ClassName\|path/to/file'`.

## Creating

```bash
ID=$(tk create "Imperative title" -t bug -p 2 --tags area,topic --external-ref PROJ-1 -d "What and where: path/File.php:line, Class::method" --design "Approach; what stays untouched" --acceptance "Checkable criteria")
```
`-t bug|feature|task|epic|chore`, `-p 0-4` (0 highest), optional `--parent <id>`, `-a <assignee>`. The description MUST name files and classes - that is what the search finds.

1. SEARCH open tickets for the files, classes and tags the new one touches; `tk show` every hit.
2. CLASSIFY each hit: "can the new ticket be started AND finished before that one is merged?" No -> `tk dep`. Yes but same files or root cause -> `tk link`. Part of it -> `--parent`. Same problem -> no new ticket, `tk add-note` on the existing one. "Better first" is priority, not a dep; depend on the narrowest real blocker, never on an epic.
3. BOTH DIRECTIONS: the new ticket may block existing ones -> `tk dep <existing> <new>`.
4. After every dep: `tk add-note <blocked> "Blocked by <id>: <reason>"`.
5. VERIFY: `tk dep cycle`; show `tk dep tree <id>`; say whether it landed in `tk ready` or `tk blocked`.

## Closing

The close rides in the commit that completes the work - never earlier, never on a branch without the work. On every commit request find the tickets it completes (`tk ls --status=in_progress`, grep open tickets for the staged paths); none -> commit as usual. No commit requested -> do not close, report "ready to close".

1. CHECK `tk show <id>`: no open **Blockers** (false dep -> `tk undep` + note; otherwise the work is not done); all **Children** closed; every acceptance criterion met, with evidence. Unmet -> do not close; splitting off the remainder is the user's call.
2. Create follow-up tickets now, so they land in the same commit.
3. STOP AND ASK. Show the evidence, the resolution, and which **Blocking** tickets really become ready (no other open blocker). Close only after an explicit yes. "It's done, commit it" authorises the commit, NOT the close - hurry does not change this.
4. `tk close <id> --reason done -m "<one line: what was delivered>"` - writes the `Closed: done - ...` note and prints what became ready. A refusal means step 1 was skipped; do not answer it with `--force`. No `ticket-close` plugin: `tk add-note <id> "Closed: done - <...>"`, then `tk super close <id>`.
5. `tk ready` -> report what became unblocked (on this branch only, until merged); last child closed -> propose closing the parent.
6. `git add .tickets/` LAST, commit with the work. Commit fails -> fix and retry. Commit abandoned -> `tk status <id> in_progress` + note `Reopened: commit abandoned`.

Note prefixes (grep `^Closed: `), written by `tk close --reason done|wontdo|duplicate|superseded [-m "<text>"] [--ref <id>]`: `Closed: done - ...` | `Closed: won't do - <why>` | `Closed: duplicate of <id>` | `Closed: superseded by <id>`.

**Won't do / duplicate / superseded:** settle every **Blocking** ticket BEFORE `tk close` - afterwards it is already falsely ready (`tk close --reason wontdo|duplicate|superseded` refuses while open dependents exist; settle them, do not `--force`). Ask the user per dependent: not needed -> `tk undep <dependent> <id>`; replaced -> `tk undep` + `tk dep <dependent> <replacement>`; pointless without it -> close it too. Each with a note. Parent: close or detach every open child first. Ticket-only commit: ask which branch.

**Reopening** a committed close: `tk add-note <id> "Reopened: <reason>"`, `tk reopen <id>`, `tk blocked` -> report what went back; commit with the rework.

## Editing

Typo, wording, priority, tags -> edit the file. New facts -> `tk add-note`, not a body rewrite. Anything that changes scope, splits or merges tickets -> read `editing.md` in this directory FIRST.

## Common mistakes

| Mistake | Fix |
|---|---|
| Closing because the work "is obviously done" | Step 3: ask first |
| Closing a won't-do ticket, then asking about dependents | Settle **Blocking** before `tk close` |
| Free-form closing note | `Closed: <resolution> - ...` prefix |
| Staging `.tickets/` before the aftermath notes | Stage last |
| Dep without a reason | `Blocked by <id>: <reason>` note |
