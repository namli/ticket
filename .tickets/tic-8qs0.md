---
id: tic-8qs0
status: open
deps: []
links: [tic-vhtd]
created: 2026-09-17T18:17:52Z
type: bug
priority: 3
assignee: namli
tags: [core]
---
# Fix silent exit of tk dep and undep on tickets without a deps field

yaml_field (ticket:135) is `sed ... | _grep "^field:" | sed ...`; under `set -o pipefail` a missing field makes grep exit 1, and callers such as cmd_dep (ticket:633 `current_deps=$(yaml_field "$file" "deps")`) and cmd_undep (ticket:908) die at that assignment without any message. Reproduced during the tic-mwhy review: a hand-written or imported ticket without a `deps:` line makes `tk super dep x y` and `tk super undep x y` exit 1 silently. plugins/ticket-dep now adds "Error: tk super dep failed", but the built-in itself still says nothing and cannot add the first dependency to such a ticket. cmd_unlink (ticket:1019) already guards its read with `|| true`; the dep side does not.

## Design

Make yaml_field tolerate a missing field (`|| true` on the grep stage, empty result), then let cmd_dep treat an empty value like `[]` and insert the field through update_yaml_field, which already appends a missing field. Check the other yaml_field callers for the same silent exit.

## Acceptance Criteria

Scenarios through `ticket super`, using the existing step `ticket "<id>" has no field "deps"`: dep on a ticket without a deps field adds `deps: [<dep-id>]` and exits 0; undep on it prints "Dependency not found" and exits 1 with that message (not silently). make test passes; CHANGELOG.md Fixed entry.

