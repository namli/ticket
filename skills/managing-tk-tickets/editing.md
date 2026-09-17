# Editing a tk ticket: scope changes, splits, merges

Read `SKILL.md` first. Body and front matter are edited in `.tickets/<id>.md`; status, deps, links and notes go only through `tk`.

1. READ `tk show <id>`: **Blockers** (what it waits for), **Blocking** (what waits for it), status. `in_progress` -> tell the user before changing scope: someone works to the old text.
2. CLASSIFY the edit:
   - Cosmetic (typo, wording, priority, tags) -> edit; after a tag change re-run the tag search.
   - Clarification (same goal, more detail) -> `tk add-note`; touch the body only if it is now wrong.
   - Scope change (other files, other acceptance criteria, other decision) -> step 3.
   - Different problem (acceptance criteria would be replaced wholesale) -> do NOT edit. Create a new ticket, `tk link` them, close the old one as `Closed: superseded by <new-id>` (SKILL.md, Closing).
3. RE-DERIVE THE GRAPH, both directions:
   - Blockers: ask again for each dep "can this be finished before that one is merged?". No longer true -> `tk undep`. Run the SKILL.md search for the NEW files and classes; add deps / links.
   - Blocking: each dependent still needs THIS outcome? If not -> `tk undep <dependent> <id>`; if it now needs more -> note there.
   - Every change gets a note on the blocked ticket: `tk dep ... --reason "<reason>"` / `tk undep ... --reason "<reason>"` write `Blocked by <id>: <reason>` / `No longer blocked by <id>: <reason>`. No `Note:` line in the output (plugin not installed) -> `tk add-note` by hand.
4. RECORD: `tk add-note <id> "Edited: <what changed and why>"`. Never delete or rewrite old notes.
5. VERIFY: `tk dep cycle`, `tk dep tree <id>`; tell the user whether the ticket and its dependents are in `tk ready` or `tk blocked`.

**Splitting:** the original becomes the parent (set `type: epic` if it keeps no work of its own), parts are created with `--parent <id>`, then MOVE each incoming dep from the parent to the part that really blocks: `tk undep <x> <parent>` + `tk dep <x> <part>`.

**Merging duplicates:** keep the older / richer ticket, copy unique facts into it as a note, re-point the other one's dependents to it, close the other as `Closed: duplicate of <id>`.

**Closed tickets are not rewritten:** reopen with `tk reopen <id> -m "<reason>"` (no plugin: a `Reopened: <reason>` note + `tk super reopen <id>`), or open a new linked ticket.
