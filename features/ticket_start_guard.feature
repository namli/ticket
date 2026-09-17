Feature: Guarded start
  As an agent working from the ticket graph
  I want tk start to refuse blocked and closed tickets
  So that work never begins on a ticket whose blockers are still open

  Background:
    Given a clean tickets directory

  # --- Guard: open blockers ---

  Scenario: Open blocker refuses the start
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And the error output should contain "Error: sg-0001 has open blockers: sg-0002"
    And the error output should contain "Use --force to start anyway, or 'tk super start' to bypass the guard"
    And the output should be empty
    And ticket "sg-0001" should have field "status" with value "open"

  Scenario: Several blockers are listed in ID order
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker B"
    And a ticket exists with ID "sg-0003" and title "Blocker C"
    And ticket "sg-0001" depends on "sg-0003"
    And ticket "sg-0001" depends on "sg-0002"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And the error output should contain "open blockers: sg-0002, sg-0003"

  Scenario: In-progress blocker refuses the start
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    And ticket "sg-0002" has status "in_progress"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And ticket "sg-0001" should have field "status" with value "open"

  Scenario: Dangling dependency refuses the start
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And ticket "sg-0001" depends on "sg-gone"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And the error output should contain "open blockers: sg-gone"

  Scenario: Closed blocker does not refuse
    Given a ticket exists with ID "sg-0001" and title "Unblocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    And ticket "sg-0002" has status "closed"
    When I run "ticket start sg-0001"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"
    And the error output should be empty
    And ticket "sg-0001" should have field "status" with value "in_progress"

  Scenario: Ticket without dependencies starts
    Given a ticket exists with ID "sg-0001" and title "Free work"
    When I run "ticket start sg-0001"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"
    And ticket "sg-0001" should have field "status" with value "in_progress"

  # --- --force ---

  Scenario: --force starts a blocked ticket and records the override
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    When I run "ticket start sg-0001 --force"
    Then the exit code should be 0
    And the error output should contain "Warning: starting sg-0001 with open blockers: sg-0002"
    And the output line 1 should contain "Updated sg-0001 -> in_progress"
    And the output line 2 should contain "Note: Forced start: open blockers sg-0002"
    And ticket "sg-0001" should have field "status" with value "in_progress"
    And ticket "sg-0001" should contain "Forced start: open blockers sg-0002"
    And ticket "sg-0001" should contain a timestamp in notes

  Scenario: --force before the ID
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    When I run "ticket start --force sg-0001"
    Then the exit code should be 0
    And ticket "sg-0001" should have field "status" with value "in_progress"

  Scenario: --force without blockers writes no note
    Given a ticket exists with ID "sg-0001" and title "Free work"
    When I run "ticket start sg-0001 --force"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"
    And the error output should be empty
    When I run "ticket show sg-0001"
    Then the output should not contain "Forced start"

  # --- Closed and already started tickets ---

  Scenario: Closed ticket is refused and pointed to tk reopen
    Given a ticket exists with ID "sg-0001" and title "Done work"
    And ticket "sg-0001" has status "closed"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And the error output should contain "Error: sg-0001 is closed - use 'tk reopen sg-0001 -m <reason> --in-progress'"
    And the output should be empty
    And ticket "sg-0001" should have field "status" with value "closed"

  Scenario: --force does not start a closed ticket
    Given a ticket exists with ID "sg-0001" and title "Done work"
    And ticket "sg-0001" has status "closed"
    When I run "ticket start sg-0001 --force"
    Then the exit code should be 1
    And the error output should contain "sg-0001 is closed"
    And ticket "sg-0001" should have field "status" with value "closed"

  Scenario: Ticket already in progress is left alone
    Given a ticket exists with ID "sg-0001" and title "Running work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    And ticket "sg-0001" has status "in_progress"
    When I run "ticket start sg-0001"
    Then the exit code should be 0
    And the output should be "sg-0001 is already in progress"
    And the error output should be empty
    And ticket "sg-0001" should have field "status" with value "in_progress"
    When I run "ticket show sg-0001"
    Then the output should not contain "Forced start"

  # --- Usage ---

  Scenario: Missing ID prints usage
    When I run "ticket start"
    Then the exit code should be 2
    And the error output should contain "Error: expected exactly one <id>"
    And the error output should contain "Usage: tk start <id> [--force]"

  Scenario: Two IDs are rejected
    Given a ticket exists with ID "sg-0001" and title "First"
    And a ticket exists with ID "sg-0002" and title "Second"
    When I run "ticket start sg-0001 sg-0002"
    Then the exit code should be 2
    And the error output should contain "Error: expected exactly one <id>"
    And ticket "sg-0001" should have field "status" with value "open"
    And ticket "sg-0002" should have field "status" with value "open"

  Scenario: Unknown flag is rejected
    Given a ticket exists with ID "sg-0001" and title "First"
    When I run "ticket start --bogus sg-0001"
    Then the exit code should be 2
    And the error output should contain "Error: unknown option: --bogus"
    And ticket "sg-0001" should have field "status" with value "open"

  Scenario: Double dash ends option parsing
    Given a ticket exists with ID "sg-0001" and title "Free work"
    When I run "ticket start -- sg-0001"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"

  Scenario: --help prints usage on stdout
    When I run "ticket start --help"
    Then the exit code should be 0
    And the output should contain "Usage: tk start <id> [--force]"
    And the error output should be empty

  Scenario: No tickets directory is an environment error
    Given the tickets directory does not exist
    When I run "ticket start sg-0001"
    Then the exit code should be 2
    And the error output should contain "no .tickets directory found"

  Scenario: Empty ID is a usage error
    Given a ticket exists with ID "sg-0001" and title "First"
    When I run "ticket start ''"
    Then the exit code should be 2
    And the error output should contain "Error: <id> must not be empty"
    And ticket "sg-0001" should have field "status" with value "open"

  # --- IDs ---

  Scenario: Partial ID is resolved to the full ID
    Given a ticket exists with ID "sg-0001" and title "Free work"
    When I run "ticket start 0001"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"

  Scenario: Unknown ID fails with core's message
    Given a ticket exists with ID "sg-0001" and title "First"
    When I run "ticket start nope"
    Then the exit code should be 1
    And the error output should contain "Error: ticket 'nope' not found"

  Scenario: Ambiguous ID fails with core's message
    Given a ticket exists with ID "sg-0001" and title "First"
    And a ticket exists with ID "sg-0002" and title "Second"
    When I run "ticket start sg-"
    Then the exit code should be 1
    And the error output should contain "Error: ambiguous ID 'sg-' matches multiple tickets"
    And ticket "sg-0001" should have field "status" with value "open"

  Scenario: ID that does not match the file name is refused
    Given a ticket exists with ID "sg-0001" and title "First"
    And a ticket exists with ID "sg-0002" and title "Second"
    And ticket "sg-0001" has raw field "id" set to "sg-0002"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And the error output should contain "Error: cannot resolve 'sg-0001'"
    And the output should be empty
    And ticket "sg-0002" should have field "status" with value "open"

  Scenario: ID line in the body is not taken for the ticket ID
    Given a ticket exists with ID "sg-0001" and title "First"
    And a ticket exists with ID "sg-0002" and title "Second"
    And ticket "sg-0001" has no field "id"
    And ticket "sg-0001" has body line "id: sg-0002"
    When I run "ticket start sg-0001"
    Then the exit code should be 1
    And the error output should contain "Error: cannot resolve 'sg-0001'"
    And ticket "sg-0002" should have field "status" with value "open"

  # --- Bypass and help ---

  Scenario: tk super start bypasses the guard
    Given a ticket exists with ID "sg-0001" and title "Blocked work"
    And a ticket exists with ID "sg-0002" and title "Blocker"
    And ticket "sg-0001" depends on "sg-0002"
    When I run "ticket super start sg-0001"
    Then the exit code should be 0
    And the output should be "Updated sg-0001 -> in_progress"

  Scenario: tk help lists the start plugin
    When I run "ticket help"
    Then the exit code should be 0
    And the output should contain "Guarded start: refuse blocked and closed tickets"
