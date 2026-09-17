Feature: Guarded reopen
  As an agent working from the ticket graph
  I want tk reopen to record why a ticket came back and what it re-blocked
  So that a reopen never silently changes which tickets are ready

  Background:
    Given a clean tickets directory

  # --- Reason is required ---

  Scenario: Reopen without -m is a usage error
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001"
    Then the exit code should be 2
    And the error output should contain "Error: -m <reason> is required"
    And the error output should contain "Usage: tk reopen <id> -m <reason> [--in-progress] [--force]"
    And ticket "rg-0001" should have field "status" with value "closed"
    When I run "ticket show rg-0001"
    Then the output should not contain "Reopened:"

  Scenario: Empty reason is a usage error
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m ''"
    Then the exit code should be 2
    And the error output should contain "Error: -m must not be empty"
    And ticket "rg-0001" should have field "status" with value "closed"

  Scenario: -m without a value is a usage error
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m"
    Then the exit code should be 2
    And the error output should contain "Error: -m requires a reason"
    And ticket "rg-0001" should have field "status" with value "closed"

  # --- Note and status ---

  Scenario: Reopen writes the note and sets open
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'parser regression in nested lists'"
    Then the exit code should be 0
    And the output line 1 should contain "Updated rg-0001 -> open"
    And the output line 2 should contain "Note: Reopened: parser regression in nested lists"
    And the output line 3 should contain "Nothing was re-blocked"
    And the error output should be empty
    And ticket "rg-0001" should have field "status" with value "open"
    And ticket "rg-0001" should contain "Reopened: parser regression in nested lists"
    And ticket "rg-0001" should contain a timestamp in notes

  Scenario: --in-progress sets in_progress
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'commit abandoned' --in-progress"
    Then the exit code should be 0
    And the output line 1 should contain "Updated rg-0001 -> in_progress"
    And ticket "rg-0001" should have field "status" with value "in_progress"
    And ticket "rg-0001" should contain "Reopened: commit abandoned"

  Scenario: Flags before the ID
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen --in-progress -m 'rework' rg-0001"
    Then the exit code should be 0
    And ticket "rg-0001" should have field "status" with value "in_progress"

  # --- Re-blocked report ---

  Scenario: Dependents whose only open blocker is the target are reported
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And a ticket exists with ID "rg-0002" and title "Waits only for 0001"
    And a ticket exists with ID "rg-0003" and title "Waits for 0001 and 0004"
    And a ticket exists with ID "rg-0004" and title "Other open blocker"
    And a ticket exists with ID "rg-0005" and title "Closed dependent"
    And a ticket exists with ID "rg-0006" and title "Also waits only for 0001"
    And ticket "rg-0001" has status "closed"
    And ticket "rg-0002" depends on "rg-0001"
    And ticket "rg-0003" depends on "rg-0001"
    And ticket "rg-0003" depends on "rg-0004"
    And ticket "rg-0005" depends on "rg-0001"
    And ticket "rg-0005" has status "closed"
    And ticket "rg-0006" depends on "rg-0001"
    When I run "ticket reopen rg-0001 -m 'regression'"
    Then the exit code should be 0
    And the output line 3 should contain "Re-blocked: rg-0002, rg-0006"
    And the output should not contain "rg-0003"
    And the output should not contain "rg-0005"

  # --- Guard: --in-progress with open blockers ---

  Scenario: --in-progress with an open blocker is refused
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And a ticket exists with ID "rg-0002" and title "Blocker"
    And ticket "rg-0001" depends on "rg-0002"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'rework' --in-progress"
    Then the exit code should be 1
    And the error output should contain "Error: rg-0001 has open blockers: rg-0002"
    And the error output should contain "Use --force to reopen as in_progress anyway, or reopen without --in-progress"
    And the output should be empty
    And ticket "rg-0001" should have field "status" with value "closed"
    When I run "ticket show rg-0001"
    Then the output should not contain "Reopened:"

  Scenario: --force overrides the blocker guard and records it
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And a ticket exists with ID "rg-0002" and title "Blocker"
    And ticket "rg-0001" depends on "rg-0002"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'rework' --in-progress --force"
    Then the exit code should be 0
    And the error output should contain "Warning: reopening rg-0001 as in_progress with open blockers: rg-0002"
    And the output line 1 should contain "Updated rg-0001 -> in_progress"
    And the output line 2 should contain "Note: Reopened: rework"
    And ticket "rg-0001" should have field "status" with value "in_progress"
    And ticket "rg-0001" should contain "Reopened: rework"
    And ticket "rg-0001" should contain "Forced: open blockers rg-0002"

  Scenario: Plain reopen with an open blocker is not refused
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And a ticket exists with ID "rg-0002" and title "Blocker"
    And ticket "rg-0001" depends on "rg-0002"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'rework'"
    Then the exit code should be 0
    And the error output should be empty
    And ticket "rg-0001" should have field "status" with value "open"
    When I run "ticket show rg-0001"
    Then the output should not contain "Forced:"

  Scenario: --force without a violation writes no Forced line
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'rework' --in-progress --force"
    Then the exit code should be 0
    And the error output should be empty
    And ticket "rg-0001" should have field "status" with value "in_progress"
    When I run "ticket show rg-0001"
    Then the output should not contain "Forced:"

  # --- Not closed ---

  Scenario: Open ticket has nothing to reopen
    Given a ticket exists with ID "rg-0001" and title "Open work"
    When I run "ticket reopen rg-0001 -m 'again'"
    Then the exit code should be 0
    And the output should be "rg-0001 is not closed (status: open) - nothing to reopen"
    When I run "ticket show rg-0001"
    Then the output should not contain "Reopened:"

  Scenario: In-progress ticket is not demoted to open
    Given a ticket exists with ID "rg-0001" and title "Running work"
    And ticket "rg-0001" has status "in_progress"
    When I run "ticket reopen rg-0001 -m 'again'"
    Then the exit code should be 0
    And the output should be "rg-0001 is not closed (status: in_progress) - nothing to reopen"
    And ticket "rg-0001" should have field "status" with value "in_progress"
    When I run "ticket show rg-0001"
    Then the output should not contain "Reopened:"

  # --- Usage ---

  Scenario: Missing ID prints usage
    When I run "ticket reopen -m 'x'"
    Then the exit code should be 2
    And the error output should contain "Error: expected exactly one <id>"

  Scenario: Two IDs are rejected
    Given a ticket exists with ID "rg-0001" and title "First"
    And a ticket exists with ID "rg-0002" and title "Second"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 rg-0002 -m 'x'"
    Then the exit code should be 2
    And the error output should contain "Error: expected exactly one <id>"
    And ticket "rg-0001" should have field "status" with value "closed"

  Scenario: Unknown flag is rejected
    Given a ticket exists with ID "rg-0001" and title "First"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg-0001 -m 'x' --bogus"
    Then the exit code should be 2
    And the error output should contain "Error: unknown option: --bogus"
    And ticket "rg-0001" should have field "status" with value "closed"

  Scenario: Double dash ends option parsing
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen -m 'rework' -- rg-0001"
    Then the exit code should be 0
    And ticket "rg-0001" should have field "status" with value "open"

  Scenario: --help prints usage on stdout
    When I run "ticket reopen --help"
    Then the exit code should be 0
    And the output should contain "Usage: tk reopen <id> -m <reason> [--in-progress] [--force]"
    And the error output should be empty

  Scenario: No tickets directory is an environment error
    Given the tickets directory does not exist
    When I run "ticket reopen rg-0001 -m 'x'"
    Then the exit code should be 2
    And the error output should contain "no .tickets directory found"

  # --- IDs ---

  Scenario: Partial ID is resolved and the full ID is reported
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen 0001 -m 'rework'"
    Then the exit code should be 0
    And the output line 1 should contain "Updated rg-0001 -> open"
    And ticket "rg-0001" should contain "Reopened: rework"

  Scenario: Unknown ID fails with core's message
    Given a ticket exists with ID "rg-0001" and title "First"
    When I run "ticket reopen nope -m 'x'"
    Then the exit code should be 1
    And the error output should contain "Error: ticket 'nope' not found"

  Scenario: Ambiguous ID fails with core's message
    Given a ticket exists with ID "rg-0001" and title "First"
    And a ticket exists with ID "rg-0002" and title "Second"
    And ticket "rg-0001" has status "closed"
    When I run "ticket reopen rg- -m 'x'"
    Then the exit code should be 1
    And the error output should contain "Error: ambiguous ID 'rg-' matches multiple tickets"
    And ticket "rg-0001" should have field "status" with value "closed"

  # --- Bypass and help ---

  Scenario: tk super reopen bypasses the guard
    Given a ticket exists with ID "rg-0001" and title "Done work"
    And ticket "rg-0001" has status "closed"
    When I run "ticket super reopen rg-0001"
    Then the exit code should be 0
    And the output should be "Updated rg-0001 -> open"
    When I run "ticket show rg-0001"
    Then the output should not contain "Reopened:"

  Scenario: tk help lists the reopen plugin
    When I run "ticket help"
    Then the exit code should be 0
    And the output should contain "Guarded reopen: record the reason, report re-blocked dependents"
