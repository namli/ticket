# Changelog

## [Unreleased]

### Changed
- Extracted `edit`, `ls`, `query`, and `migrate-beads` commands to plugins (ticket-extras)
- `ready` output shows the ticket type after the status: `id [P2][open][task] - title` (tickets without a `type` field show `task`)

### Added
- Plugin system: executables named `tk-<cmd>` or `ticket-<cmd>` in PATH are invoked automatically
- `super` command to bypass plugins and run built-in commands directly
- `TICKETS_DIR` and `TK_SCRIPT` environment variables exported for plugins
- `help` command lists installed plugins with descriptions
- Plugin metadata: `# tk-plugin:` comment for scripts, `--tk-describe` flag for binaries
- Multi-package distribution: `ticket-core`, `ticket-extras`, and individual plugin packages
- CI scripts for publishing to Homebrew tap and AUR

### Plugins
- ticket-edit 1.0.0: Open ticket in $EDITOR (extracted from core)
- ticket-ls 1.0.0: List tickets with optional filters (extracted from core); `ticket-list` symlink for alias
- ticket-query 1.0.0: Output tickets as JSON, optionally filtered with jq (extracted from core)
- ticket-migrate-beads 1.0.0: Import tickets from .beads/issues.jsonl (extracted from core)
- ticket-lint 1.0.0: New plugin, `tk lint [--conventions] [--strict]` checks tickets for broken graph invariants (self-deps, cycles, missing references, asymmetric links, invalid fields) in `file:line: level: message [rule]` format
- ticket-find 1.0.0: New plugin, `tk find [--all] [-T tag] <pattern>...` searches title, body and notes of non-closed tickets (case-insensitive extended regex, patterns OR-ed) and prints `id [P2][open] - title` lines; exit 1 when nothing matches
- ticket-impact 1.0.0: New plugin, `tk impact [--porcelain] <id>` shows what closing a ticket would change (open blockers and children, dependents that become ready or stay blocked, last open child of a parent); `--porcelain` prints one stable fact per line for other plugins
- ticket-start 1.0.0: New plugin, shadows `tk start`: refuses a ticket with open blockers (`--force` overrides and writes a `Forced start:` note) and always refuses a closed ticket; needs `ticket-impact`; `tk super start` bypasses it
- ticket-reopen 1.0.0: New plugin, shadows `tk reopen`: `tk reopen <id> -m <reason> [--in-progress] [--force]` writes a `Reopened: <reason>` note, can restore `in_progress`, reports re-blocked dependents and leaves tickets that are not closed alone; needs `ticket-impact`; `tk super reopen` bypasses it
- ticket-dep 1.0.0: New plugin, shadows `tk dep` / `tk undep` (`ticket-undep` is a symlink to it): rejects self-dependencies and cycles (closed tickets count as edges), compares dependency IDs exactly, requires `--reason <text>` (or `--no-note`) and writes `Blocked by <dep-id>: <text>` / `No longer blocked by <dep-id>: <text>`, prints whether the ticket is ready or blocked, `undep` refuses when the built-in's unanchored removal would damage a sibling dependency; `tk dep tree` / `tk dep cycle` pass through; bypass with `tk super dep`
- ticket-close 1.0.0: New plugin that shadows the built-in, `tk close <id> --reason done|wontdo|duplicate|superseded [-m text] [--ref id] [--force]`: refuses open blockers, open children and (for won't-do / duplicate / superseded) open dependents, writes the `Closed: <resolution>` note, prints the tickets that became ready and the last-open-child hint; requires ticket-impact; `tk super close` bypasses it

## [0.3.2] - 2026-02-03

### Fixed
- Ticket ID lookup now trims leading/trailing whitespace (fixes issue with AI agents passing extra spaces)

## [0.3.1] - 2026-01-28

### Added
- `list` command alias for `ls`
- `TICKET_PAGER` environment variable for `show` command (only when stdout is a TTY; falls back to `PAGER`)

### Changed
- Walk parent directories to find `.tickets/` directory, enabling commands from any subdirectory
- Ticket ID suffix now uses full alphanumeric (a-z0-9) instead of hex for increased entropy

### Fixed
- `dep` command now resolves partial IDs for the dependency argument
- `undep` command now resolves partial IDs and validates dependency exists
- `unlink` command now resolves partial IDs for both arguments
- `create --parent` now validates and resolves parent ticket ID
- `generate_id` now uses 3-char prefix for single-segment directory names (e.g., "plan" → "pla" instead of "p")

## [0.3.0] - 2026-01-18

### Added
- Support `TICKETS_DIR` environment variable for custom tickets directory location
- `dep cycle` command to detect dependency cycles in open tickets
- `add-note` command for appending timestamped notes to tickets
- `-a, --assignee` filter flag for `ls`, `ready`, `blocked`, and `closed` commands
- `--tags` flag for `create` command to add comma-separated tags
- `-T, --tag` filter flag for `ls`, `ready`, `blocked`, and `closed` commands

## [0.2.0] - 2026-01-04

### Added
- `--parent` flag for `create` command to set parent ticket
- `link`/`unlink` commands for symmetric ticket relationships
- `show` command displays parent title and linked tickets
- `migrate-beads` now imports parent-child and related dependencies

## [0.1.1] - 2026-01-02

### Fixed
- `edit` command no longer hangs when run in non-TTY environments

## [0.1.0] - 2026-01-02

Initial release.
