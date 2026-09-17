# ticket

The git-backed issue tracker for AI agents. Rooted in the Unix Philosophy, `tk` is inspired by Joe Armstrong's [Minimal Viable Program](https://joearms.github.io/published/2014-06-25-minimal-viable-program.html) with additional quality of life features for managing and querying against complex issue dependency graphs.

`tk` was written as a full replacement for [beads](https://github.com/steveyegge/beads). It shares many similar commands but without the need for keeping a SQLite file in sync or a rogue background daemon mangling your changes. It ships with a `migrate-beads` command to make this a smooth transition.

Tickets are markdown files with YAML frontmatter in `.tickets/`. This allows AI agents to easily search them for relevant content without dumping ten thousand character JSONL lines into their context window.

Using ticket IDs as file names also allows IDEs to quickly navigate to the ticket for you. For example, you might run `git log` in your terminal and see something like:

```
nw-5c46: add SSE connection management 
```

VS Code allows you to Ctrl+Click or Cmd+Click the ID and jump directly to the file to read the details.

## Install

**Homebrew (macOS/Linux):**
```bash
brew tap wedow/tools
brew install ticket
```

**Arch Linux (AUR):**
```bash
yay -S ticket  # or paru, etc.
```

**From source (auto-updates on git pull):**
```bash
git clone https://github.com/wedow/ticket.git
cd ticket && ln -s "$PWD/ticket" ~/.local/bin/tk
```

**Or** just copy `ticket` to somewhere in your PATH.

## Requirements

`tk` is a portable bash script requiring only coreutils, so it works out of the box on any POSIX system with bash installed. The `query` command requires `jq`. Uses `rg` (ripgrep) if available, falls back to `grep`.

## Agent Setup

Add this line to your `CLAUDE.md` or `AGENTS.md`:

```
This project uses a CLI ticket system for task management. Run `tk help` when you need to use it.
```

Claude Opus picks it up naturally from there. Other models may need additional guidance.

### Agent skill

`tk` validates almost nothing, so the dependency graph stays accurate only if the agent follows some conventions. The [`managing-tk-tickets`](skills/managing-tk-tickets/SKILL.md) skill teaches them: search the backlog before creating a ticket, choose between `dep`, `link` and `--parent`, check for cycles, and close a ticket only in the commit that completes the work, after asking.

To install it for Claude Code, copy or symlink the directory into your skills folder:

```bash
ln -s "$PWD/skills/managing-tk-tickets" ~/.claude/skills/managing-tk-tickets
```

## Usage

```bash
tk - minimal ticket system with dependency tracking

Usage: tk <command> [args]

Commands:
  create [title] [options] Create ticket, prints ID
    -d, --description      Description text
    --design               Design notes
    --acceptance           Acceptance criteria
    -t, --type             Type (bug|feature|task|epic|chore) [default: task]
    -p, --priority         Priority 0-4, 0=highest [default: 2]
    -a, --assignee         Assignee [default: git user.name]
    --external-ref         External reference (e.g., gh-123, JIRA-456)
    --parent               Parent ticket ID
    --tags                 Comma-separated tags (e.g., --tags ui,backend,urgent)
  start <id>               Set status to in_progress
  close <id>               Set status to closed
  reopen <id>              Set status to open
  status <id> <status>     Update status (open|in_progress|closed)
  dep <id> <dep-id>        Add dependency (id depends on dep-id)
  dep tree [--full] <id>   Show dependency tree (--full disables dedup)
  dep cycle                Find dependency cycles in open tickets
  undep <id> <dep-id>      Remove dependency
  link <id> <id> [id...]   Link tickets together (symmetric)
  unlink <id> <target-id>  Remove link between tickets
  ls|list [--status=X] [-a X] [-T X]   List tickets
  ready [-a X] [-T X]      List open/in-progress tickets with deps resolved
  blocked [-a X] [-T X]    List open/in-progress tickets with unresolved deps
  closed [--limit=N] [-a X] [-T X] List recently closed tickets (default 20, by mtime)
  show <id>                Display ticket
  add-note <id> [text]     Append timestamped note (or pipe via stdin)
  super <cmd> [args]       Bypass plugins, run built-in command directly

Bundled plugins (ticket-extras):
  edit <id>                Open ticket in $EDITOR
  ls|list [--status=X] [-a X] [-T X]   List tickets
  query [jq-filter]        Output tickets as JSON, optionally filtered (requires jq)
  migrate-beads            Import tickets from .beads/issues.jsonl (requires jq)

Official plugins (installed separately):
  dep <id> <dep-id> --reason X     Guarded dep (shadows the built-in): rejects self-deps and
                           cycles, notes 'Blocked by <dep-id>: X', prints ready/blocked state
  undep <id> <dep-id> --reason X   Guarded undep: notes 'No longer blocked by <dep-id>: X'
                           (--no-note instead of --reason skips the note; dep tree / dep cycle unchanged)
  find [--all] [-T X] <pattern>...   Search title, body and notes (case-insensitive regex,
                           patterns OR-ed); closed tickets only with --all; exit 1 on no match
  lint [--conventions] [--strict]    Check tickets for broken graph invariants
  impact [--porcelain] <id>          Show what closing a ticket would change
  start <id> [--force]     Guarded start: refuse tickets with open blockers and closed tickets
  reopen <id> -m <reason> [--in-progress] [--force]
                           Guarded reopen: write a 'Reopened:' note, report re-blocked dependents
  close <id> --reason done|wontdo|duplicate|superseded [-m text] [--ref id] [--force]
                           Guarded close, shadows the built-in (needs impact): refuses open
                           blockers/children, writes the Closed: note, lists what became ready

Searches parent directories for .tickets/ (override with TICKETS_DIR env var)
Supports partial ID matching (e.g., 'tk show 5c4' matches 'nw-5c46')
```

## Plugins

Executables named `tk-<cmd>` or `ticket-<cmd>` in your PATH are invoked automatically. This allows you to add custom commands or override built-in ones.

```bash
# Create a simple plugin
cat > ~/.local/bin/tk-hello <<'EOF'
#!/bin/bash
# tk-plugin: Say hello
echo "Hello from plugin!"
EOF
chmod +x ~/.local/bin/tk-hello

# Now it's available
tk hello        # runs tk-hello
tk help         # lists it under "Plugins"
```

**Plugin descriptions** (shown in `tk help`):
- Scripts: comment `# tk-plugin: description` in first 10 lines
- Binaries: `--tk-describe` flag outputs `tk-plugin: description`

**Plugin environment variables:**
- `TICKETS_DIR` - path to the .tickets directory (may be empty)
- `TK_SCRIPT` - absolute path to the tk script

**Calling built-ins from plugins:**
```bash
#!/bin/bash
# tk-plugin: Custom create with extras
id=$("$TK_SCRIPT" super create "$@")
echo "Created $id, doing extra stuff..."
```

Use `tk super <cmd>` to bypass plugins and run the built-in directly.

**Official plugins** live in [`plugins/`](plugins/README.md). Besides the bundled ones, `ticket-lint` (`tk lint`) checks the whole ticket graph for broken invariants - self-dependencies, cycles, dangling references, one-sided links - and works as a pre-commit hook. `ticket-find` (`tk find <pattern>...`) searches ticket titles, bodies and notes - the content `tk query` does not return - and prints matching non-closed tickets as list lines. `ticket-impact` (`tk impact <id>`) shows what closing a ticket would change - which dependents become ready, which stay blocked, open blockers and children - and has a `--porcelain` mode for scripts. `ticket-start` and `ticket-reopen` shadow the built-in `tk start` and `tk reopen` with guards: `tk start <id>` refuses a ticket with open blockers (`--force` overrides) and a closed ticket, and `tk reopen <id> -m <reason> [--in-progress]` writes a `Reopened:` note and reports which dependents went back to blocked. Both need `ticket-impact` on your PATH; `tk super start` / `tk super reopen` run the unguarded built-ins. `ticket-close` shadows `tk close` with a guard: `tk close <id> --reason done|wontdo|duplicate|superseded` refuses a ticket with open blockers or open children (and, for the reasons that deliver nothing, one that open tickets still depend on), writes the `Closed: <resolution>` note and prints which tickets became ready; it needs `ticket-impact`, `--force` overrides the guard and `tk super close` bypasses it. `ticket-dep` (with its `ticket-undep` symlink) shadows the built-in `tk dep` / `tk undep`: it rejects self-dependencies and cycles and requires a `--reason`, which it records as a note on the blocked ticket; `tk super dep` bypasses it. None of them is part of `ticket-extras`: copy or symlink `plugins/ticket-lint`, `plugins/ticket-find`, `plugins/ticket-impact`, `plugins/ticket-start`, `plugins/ticket-reopen`, `plugins/ticket-close` and `plugins/ticket-dep` (with the `plugins/ticket-undep` symlink) into your PATH (or put the `plugins/` directory on your PATH), or install the `ticket-lint`, `ticket-find`, `ticket-impact`, `ticket-start`, `ticket-reopen`, `ticket-close` and `ticket-dep` packages.

## Testing

The tests are written in the Behavior-Driven Development library [behave](https://behave.readthedocs.io/en/latest/) and require Python.

If you have `uv` [installed](https://docs.astral.sh/uv/getting-started/installation/) simply:

```sh
make test
```

## Migrating from Beads

```bash
tk migrate-beads

# review new files if you like
git status

# check state matches expectations
tk ready
tk blocked

# compare against
bd ready
bd blocked

# all good, let's go
git rm -rf .beads
git add .tickets
git commit -am "ditch beads"
```

For a thorough system-wide Beads cleanup, see [banteg's uninstall script](https://gist.github.com/banteg/1a539b88b3c8945cd71e4b958f319d8d).

## License

MIT
