Feature: Set ticket fields
  As a user or an agent
  I want tk set to change title, priority, type, assignee, tags and parent
  So that nobody has to hand-edit front matter

  Background:
    Given a clean tickets directory
    And a ticket exists with ID "set-0001" and title "First"
    And a ticket exists with ID "set-0002" and title "Second"
    And a ticket exists with ID "set-0003" and title "Third" with parent "set-0002"

  # --- Scalar fields ---

  Scenario: Set priority
    When I run "ticket set set-0001 priority 0"
    Then the exit code should be 0
    And the output line 1 should contain "Updated set-0001: priority 2 -> 0"
    And ticket "set-0001" should have field "priority" with value "0"

  Scenario: show reflects the new priority
    When I run "ticket set set-0001 priority 4"
    And I run "ticket show set-0001"
    Then the output should contain "priority: 4"

  Scenario: The ticket is found by partial ID
    When I run "ticket set 0001 priority 1"
    Then the exit code should be 0
    And ticket "set-0001" should have field "priority" with value "1"

  Scenario: Invalid priority is rejected
    When I run "ticket set set-0001 priority 5"
    Then the exit code should be 1
    And the error output should contain "invalid priority '5'"
    And ticket "set-0001" should have field "priority" with value "2"

  Scenario: Non-numeric priority is rejected
    When I run "ticket set set-0001 priority high"
    Then the exit code should be 1
    And the error output should contain "invalid priority 'high'"

  Scenario: Set type
    When I run "ticket set set-0001 type bug"
    Then the exit code should be 0
    And the output line 1 should contain "Updated set-0001: type task -> bug"
    And ticket "set-0001" should have field "type" with value "bug"

  Scenario: Invalid type is rejected
    When I run "ticket set set-0001 type story"
    Then the exit code should be 1
    And the error output should contain "invalid type 'story'"
    And the error output should contain "bug|feature|task|epic|chore"
    And ticket "set-0001" should have field "type" with value "task"

  Scenario: Set assignee on a ticket that has none
    When I run "ticket set set-0001 assignee 'Jane Doe'"
    Then the exit code should be 0
    And the output line 1 should contain "Updated set-0001: assignee none -> Jane Doe"
    And ticket "set-0001" should have field "assignee" with value "Jane Doe"

  Scenario: A new field lands inside the front matter
    When I run "ticket set set-0001 assignee jane"
    And I run "ticket query '.assignee'"
    Then the output should contain "jane"

  Scenario: Assignee none removes the field
    Given ticket "set-0001" has raw field "assignee" set to "jane"
    When I run "ticket set set-0001 assignee none"
    Then the exit code should be 0
    And the output line 1 should contain "Updated set-0001: assignee jane -> none"
    And ticket "set-0001" should not contain "assignee:"

  # --- Title ---

  Scenario: Set title
    When I run "ticket set set-0001 title 'Renamed ticket'"
    Then the exit code should be 0
    And the output line 1 should contain "Updated set-0001: title First -> Renamed ticket"
    And ticket "set-0001" should contain "# Renamed ticket"
    And ticket "set-0001" should not contain "# First"

  Scenario: show reflects the new title
    When I run "ticket set set-0001 title 'Renamed ticket'"
    And I run "ticket show set-0001"
    Then the output should contain "# Renamed ticket"

  Scenario: Only the first heading is rewritten
    Given ticket "set-0001" has body line "# Appendix"
    When I run "ticket set set-0001 title 'Renamed ticket'"
    Then the exit code should be 0
    And ticket "set-0001" should contain "# Appendix"

  Scenario: Title with slash, ampersand and backslash survives
    When I run "ticket set set-0001 title 'Fix a/b & c\d in src/x'"
    Then the exit code should be 0
    And ticket "set-0001" should contain "# Fix a/b & c\d in src/x"

  Scenario: Assignee with slash and ampersand survives
    When I run "ticket set set-0001 assignee 'ops/R&D'"
    Then the exit code should be 0
    And ticket "set-0001" should have field "assignee" with value "ops/R&D"

  Scenario: Empty title is rejected
    When I run "ticket set set-0001 title ''"
    Then the exit code should be 1
    And the error output should contain "title must not be empty"
    And ticket "set-0001" should contain "# First"

  Scenario: A multi-line value is rejected
    When I run "ticket set set-0001 assignee \"$(printf 'jane\nstatus: closed')\""
    Then the exit code should be 1
    And the error output should contain "assignee must be a single line"
    And ticket "set-0001" should not contain "assignee:"

  Scenario: Surrounding blanks are trimmed
    When I run "ticket set set-0001 assignee '  jane  '"
    Then the exit code should be 0
    And the output line 1 should contain "Updated set-0001: assignee none -> jane"
    And ticket "set-0001" should have field "assignee" with value "jane"

  # --- Front matter only ---

  Scenario: A body line that looks like a field is left alone
    Given ticket "set-0001" has body line "priority: high"
    When I run "ticket set set-0001 priority 1"
    Then the exit code should be 0
    And ticket "set-0001" should have field "priority" with value "1"
    And ticket "set-0001" should contain "priority: high"

  # --- Tags ---

  Scenario: Set tags replaces the list
    Given ticket "set-0001" has raw field "tags" set to "[old]"
    When I run "ticket set set-0001 tags ui,backend"
    Then the exit code should be 0
    And the output line 1 should contain "Updated set-0001: tags [old] -> [ui, backend]"
    And ticket "set-0001" should have field "tags" with value "[ui, backend]"

  Scenario: Set tags on a ticket that has none
    When I run "ticket set set-0001 tags ui"
    Then the exit code should be 0
    And ticket "set-0001" should have field "tags" with value "[ui]"

  Scenario: Plus adds a tag
    Given ticket "set-0001" has raw field "tags" set to "[ui]"
    When I run "ticket set set-0001 tags +urgent"
    Then the exit code should be 0
    And ticket "set-0001" should have field "tags" with value "[ui, urgent]"

  Scenario: Adding an existing tag changes nothing
    Given ticket "set-0001" has raw field "tags" set to "[ui]"
    When I run "ticket set set-0001 tags +ui"
    Then the exit code should be 0
    And the output should contain "set-0001: tags unchanged"
    And ticket "set-0001" should not contain "Edited:"

  Scenario: Minus removes a tag
    Given ticket "set-0001" has raw field "tags" set to "[ui, backend]"
    When I run "ticket set set-0001 tags -- -ui"
    Then the exit code should be 0
    And ticket "set-0001" should have field "tags" with value "[backend]"

  Scenario: Add and remove in one call
    Given ticket "set-0001" has raw field "tags" set to "[ui, backend]"
    When I run "ticket set set-0001 tags +urgent,-ui"
    Then the exit code should be 0
    And ticket "set-0001" should have field "tags" with value "[backend, urgent]"

  Scenario: Removing the last tag removes the field
    Given ticket "set-0001" has raw field "tags" set to "[ui]"
    When I run "ticket set set-0001 tags -- -ui"
    Then the exit code should be 0
    And ticket "set-0001" should not contain "tags:"

  Scenario: Tags none removes the field
    Given ticket "set-0001" has raw field "tags" set to "[ui, backend]"
    When I run "ticket set set-0001 tags none"
    Then the exit code should be 0
    And the output line 1 should contain "Updated set-0001: tags [ui, backend] -> none"
    And ticket "set-0001" should not contain "tags:"

  Scenario: Mixing plain and signed tags is rejected
    Given ticket "set-0001" has raw field "tags" set to "[ui]"
    When I run "ticket set set-0001 tags backend,+urgent"
    Then the exit code should be 1
    And the error output should contain "cannot mix"
    And ticket "set-0001" should have field "tags" with value "[ui]"

  Scenario: A tag with brackets is rejected
    When I run "ticket set set-0001 tags 'ui,[x]'"
    Then the exit code should be 1
    And the error output should contain "invalid tag '[x]'"
    And ticket "set-0001" should not contain "tags:"

  # --- Parent ---

  Scenario: Set parent through a partial ID
    When I run "ticket set set-0001 parent 0002"
    Then the exit code should be 0
    And the output line 1 should contain "Updated set-0001: parent none -> set-0002"
    And ticket "set-0001" should have field "parent" with value "set-0002"

  Scenario: show lists the ticket under its new parent
    When I run "ticket set set-0001 parent set-0002"
    And I run "ticket show set-0002"
    Then the output should contain "set-0001"

  Scenario: Parent none removes the field
    When I run "ticket set set-0003 parent none"
    Then the exit code should be 0
    And the output line 1 should contain "Updated set-0003: parent set-0002 -> none"
    And ticket "set-0003" should not contain "parent:"

  Scenario: Missing parent is rejected
    When I run "ticket set set-0001 parent nope-9999"
    Then the exit code should be 1
    And the error output should contain "ticket 'nope-9999' not found"
    And ticket "set-0001" should not contain "parent:"

  Scenario: A ticket cannot be its own parent
    When I run "ticket set set-0001 parent set-0001"
    Then the exit code should be 1
    And the error output should contain "set-0001 cannot be its own parent"
    And ticket "set-0001" should not contain "parent:"

  Scenario: A child cannot become the parent
    When I run "ticket set set-0002 parent set-0003"
    Then the exit code should be 1
    And the error output should contain "set-0003 is a descendant of set-0002"
    And ticket "set-0002" should not contain "parent:"

  Scenario: A grandchild cannot become the parent
    Given a ticket exists with ID "set-0004" and title "Fourth" with parent "set-0003"
    When I run "ticket set set-0002 parent set-0004"
    Then the exit code should be 1
    And the error output should contain "set-0004 is a descendant of set-0002"
    And the error output should contain "set-0004 -> set-0003 -> set-0002"

  # --- Refused fields ---

  Scenario: status is refused with a hint
    When I run "ticket set set-0001 status closed"
    Then the exit code should be 1
    And the error output should contain "status is not set here"
    And the error output should contain "tk start"
    And ticket "set-0001" should have field "status" with value "open"

  Scenario: deps is refused with a hint
    When I run "ticket set set-0001 deps set-0002"
    Then the exit code should be 1
    And the error output should contain "deps is not set here"
    And the error output should contain "tk dep"
    And ticket "set-0001" should contain "deps: []"

  Scenario: links is refused with a hint
    When I run "ticket set set-0001 links set-0002"
    Then the exit code should be 1
    And the error output should contain "tk link"

  Scenario: id is refused
    When I run "ticket set set-0001 id set-9999"
    Then the exit code should be 1
    And the error output should contain "id cannot be changed"

  Scenario: Unknown field is rejected
    When I run "ticket set set-0001 colour red"
    Then the exit code should be 2
    And the error output should contain "unknown field 'colour'"
    And the error output should contain "title, priority, type, assignee, tags, parent"

  # --- Notes ---

  Scenario: The change is recorded as a note
    When I run "ticket set set-0001 priority 0"
    Then the exit code should be 0
    And the output line 2 should contain "Note: Edited: priority 2 -> 0"
    And ticket "set-0001" should contain "Edited: priority 2 -> 0"
    And ticket "set-0001" should contain a timestamp in notes

  Scenario: --no-note skips the note
    When I run "ticket set set-0001 priority 0 --no-note"
    Then the exit code should be 0
    And ticket "set-0001" should have field "priority" with value "0"
    And ticket "set-0001" should not contain "Edited:"
    And the output line count should be 1

  Scenario: An unchanged value writes nothing
    When I run "ticket set set-0001 priority 2"
    Then the exit code should be 0
    And the output should be "set-0001: priority unchanged"
    And ticket "set-0001" should not contain "Edited:"

  Scenario: A closed ticket can still be edited
    Given ticket "set-0001" has status "closed"
    When I run "ticket set set-0001 priority 3"
    Then the exit code should be 0
    And ticket "set-0001" should have field "priority" with value "3"

  # --- Usage ---

  Scenario: Missing value is a usage error
    When I run "ticket set set-0001 priority"
    Then the exit code should be 2
    And the error output should contain "Usage: tk set"

  Scenario: Unknown option is a usage error
    When I run "ticket set set-0001 priority 1 --force"
    Then the exit code should be 2
    And the error output should contain "unknown option: --force"

  Scenario: Help is printed
    When I run "ticket set --help"
    Then the exit code should be 0
    And the output should contain "Usage: tk set"

  Scenario: Unknown ticket is rejected
    When I run "ticket set nope-9999 priority 1"
    Then the exit code should be 1
    And the error output should contain "ticket 'nope-9999' not found"

  Scenario: set is listed in help
    When I run "ticket help"
    Then the output should match pattern "set +Change title, priority, type, assignee, tags or parent"
