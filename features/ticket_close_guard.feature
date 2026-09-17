Feature: Guarded Close
  As a user or an agent
  I want tk close to refuse unsafe closes and record why a ticket was closed
  So that dependents never become ready by mistake

  Background:
    Given a clean tickets directory

  # --- Note text ---

  Scenario: Done note
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done -m \"guard plugin shipped\""
    Then the exit code should be 0
    And the output line 1 should contain "Updated cl-0001 -> closed"
    And the output line 2 should contain "Note: Closed: done - guard plugin shipped"
    And ticket "cl-0001" should contain "Closed: done - guard plugin shipped"
    And ticket "cl-0001" should contain a timestamp in notes

  Scenario: Won't-do note
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason wontdo -m \"out of scope\""
    Then the exit code should be 0
    And ticket "cl-0001" should contain "Closed: won't do - out of scope"

  Scenario: Duplicate note
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Original"
    When I run "ticket close cl-0001 --reason duplicate --ref cl-0002"
    Then the exit code should be 0
    And the output line 2 should contain "Note: Closed: duplicate of cl-0002"
    And ticket "cl-0001" should contain "Closed: duplicate of cl-0002"

  Scenario: Superseded note with a text
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Replacement"
    When I run "ticket close cl-0001 --reason superseded --ref cl-0002 -m \"merged scope\""
    Then the exit code should be 0
    And ticket "cl-0001" should contain "Closed: superseded by cl-0002 - merged scope"

  Scenario: Duplicate note with a text
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Original"
    When I run "ticket close cl-0001 --reason duplicate --ref cl-0002 -m \"same bug\""
    Then the exit code should be 0
    And ticket "cl-0001" should contain "Closed: duplicate of cl-0002 - same bug"

  Scenario: Partial --ref is written as the full ID
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Original"
    When I run "ticket close cl-0001 --reason=duplicate --ref=0002"
    Then the exit code should be 0
    And ticket "cl-0001" should contain "Closed: duplicate of cl-0002"

  Scenario: A closed ticket may be the --ref
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Original"
    And ticket "cl-0002" has status "closed"
    When I run "ticket close cl-0001 --reason duplicate --ref cl-0002"
    Then the exit code should be 0

  # --- Usage errors ---

  Scenario: Missing --reason is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001"
    Then the exit code should be 2
    And the error output should contain "Error: --reason is required"
    And the error output should contain "Usage: tk close <id> --reason done|wontdo|duplicate|superseded"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Invalid reason is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason fixed -m \"x\""
    Then the exit code should be 2
    And the error output should contain "invalid --reason 'fixed'"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Done without -m is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done"
    Then the exit code should be 2
    And the error output should contain "--reason done requires -m <text>"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Won't-do without -m is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason wontdo"
    Then the exit code should be 2
    And the error output should contain "--reason wontdo requires -m <text>"

  Scenario: Empty -m is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done -m \" \""
    Then the exit code should be 2
    And the error output should contain "-m must not be empty"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Duplicate without --ref is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason duplicate"
    Then the exit code should be 2
    And the error output should contain "--reason duplicate requires --ref <id>"

  Scenario: --ref with done is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Other"
    When I run "ticket close cl-0001 --reason done -m \"x\" --ref cl-0002"
    Then the exit code should be 2
    And the error output should contain "--ref is only valid with --reason duplicate|superseded"

  Scenario: Unknown flag is a usage error
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done -m \"x\" --yes"
    Then the exit code should be 2
    And the error output should contain "unknown option: --yes"

  Scenario: No ID is a usage error
    When I run "ticket close --reason done -m \"x\""
    Then the exit code should be 2
    And the error output should contain "expected exactly one <id>"

  Scenario: Two IDs are a usage error
    Given a ticket exists with ID "cl-0001" and title "First"
    And a ticket exists with ID "cl-0002" and title "Second"
    When I run "ticket close cl-0001 cl-0002 --reason done -m \"x\""
    Then the exit code should be 2
    And ticket "cl-0001" should have field "status" with value "open"
    And ticket "cl-0002" should have field "status" with value "open"

  Scenario: Flags may come before the ID
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close --reason=done -m \"shipped\" cl-0001"
    Then the exit code should be 0
    And ticket "cl-0001" should have field "status" with value "closed"

  Scenario: Help prints usage and exits 0
    When I run "ticket close --help"
    Then the exit code should be 0
    And the output should contain "Usage: tk close <id> --reason"
    And the output should contain "Bypass the guard: tk super close <id>"

  # --- ID resolution ---

  Scenario: Partial target ID works
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close 0001 --reason done -m \"shipped\""
    Then the exit code should be 0
    And the output line 1 should contain "Updated cl-0001 -> closed"

  Scenario: Unknown ID fails with core's message
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close nope --reason done -m \"x\""
    Then the exit code should be 1
    And the error output should contain "ticket 'nope' not found"

  Scenario: Ambiguous ID fails
    Given a ticket exists with ID "cl-0001" and title "First"
    And a ticket exists with ID "cl-0002" and title "Second"
    When I run "ticket close cl- --reason done -m \"x\""
    Then the exit code should be 1
    And the error output should contain "ambiguous ID 'cl-' matches multiple tickets"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Unknown --ref fails and leaves the target open
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason duplicate --ref nope"
    Then the exit code should be 1
    And the error output should contain "ticket 'nope' not found"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: A ticket cannot be a duplicate of itself
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason duplicate --ref 0001"
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 cannot be a duplicate of itself"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: A ticket cannot be superseded by itself
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason superseded --ref cl-0001"
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 cannot be superseded by itself"

  # --- Already closed ---

  Scenario: Closing a closed ticket changes nothing
    Given a ticket exists with ID "cl-0001" and title "Target"
    And ticket "cl-0001" has status "closed"
    When I run "ticket close cl-0001 --reason done -m \"again\""
    Then the exit code should be 0
    And the output should be "cl-0001 is already closed"
    When I run "ticket show cl-0001"
    Then the output should not contain "Closed:"

  # --- Bypass ---

  Scenario: tk super close bypasses the guard
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker"
    And ticket "cl-0001" depends on "cl-0002"
    When I run "ticket super close cl-0001"
    Then the exit code should be 0
    And the output should be "Updated cl-0001 -> closed"
    And ticket "cl-0001" should have field "status" with value "closed"
    When I run "ticket show cl-0001"
    Then the output should not contain "Closed:"

  # --- Guards: open blockers and open children ---

  Scenario: Open blocker refuses the close
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker"
    And ticket "cl-0001" depends on "cl-0002"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 has open blockers: cl-0002"
    And the error output should contain "Use --force to close anyway, or 'tk super close' to bypass the guard"
    And the output should be empty
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: A refused close writes no note
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker"
    And ticket "cl-0001" depends on "cl-0002"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    And I run "ticket show cl-0001"
    Then the output should not contain "Closed:"

  Scenario: Open child refuses the close
    Given a ticket exists with ID "cl-0001" and title "Parent"
    And a ticket exists with ID "cl-0002" and title "Child" with parent "cl-0001"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 has open children: cl-0002"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Every violation is reported at once
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker one"
    And a ticket exists with ID "cl-0003" and title "Blocker two"
    And a ticket exists with ID "cl-0004" and title "Child" with parent "cl-0001"
    And ticket "cl-0001" depends on "cl-0002"
    And ticket "cl-0001" depends on "cl-0003"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 has open blockers: cl-0002, cl-0003"
    And the error output should contain "Error: cl-0001 has open children: cl-0004"

  Scenario: Closed blocker and closed child do not refuse
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker"
    And a ticket exists with ID "cl-0003" and title "Child" with parent "cl-0001"
    And ticket "cl-0001" depends on "cl-0002"
    And ticket "cl-0002" has status "closed"
    And ticket "cl-0003" has status "closed"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 0
    And ticket "cl-0001" should have field "status" with value "closed"
    And the error output should be empty

  # --- Guards: open dependents of a close that delivers nothing ---

  Scenario: Won't-do close with an open dependent is refused
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason wontdo -m \"out of scope\""
    Then the exit code should be 1
    And the error output should contain "Error: cl-0001 has open dependents that would see it as resolved: cl-0002"
    And the error output should contain "tk undep"
    And ticket "cl-0001" should have field "status" with value "open"

  Scenario: Duplicate close with an open dependent is refused
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And a ticket exists with ID "cl-0003" and title "Original"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason duplicate --ref cl-0003"
    Then the exit code should be 1
    And the error output should contain "open dependents that would see it as resolved: cl-0002"

  Scenario: Superseded close with an open dependent is refused
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And a ticket exists with ID "cl-0003" and title "Replacement"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason superseded --ref cl-0003"
    Then the exit code should be 1
    And the error output should contain "open dependents that would see it as resolved: cl-0002"

  Scenario: A dependent that is also blocked by another ticket still counts
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And a ticket exists with ID "cl-0003" and title "Other blocker"
    And ticket "cl-0002" depends on "cl-0001"
    And ticket "cl-0002" depends on "cl-0003"
    When I run "ticket close cl-0001 --reason wontdo -m \"out of scope\""
    Then the exit code should be 1
    And the error output should contain "open dependents that would see it as resolved: cl-0002"

  Scenario: Done close with open dependents is allowed
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 0
    And ticket "cl-0001" should have field "status" with value "closed"

  Scenario: Closed dependents do not refuse a won't-do close
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And ticket "cl-0002" depends on "cl-0001"
    And ticket "cl-0002" has status "closed"
    When I run "ticket close cl-0001 --reason wontdo -m \"out of scope\""
    Then the exit code should be 0
    And ticket "cl-0001" should have field "status" with value "closed"

  # --- --force ---

  Scenario: Force closes despite blocker and child and records it
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Blocker"
    And a ticket exists with ID "cl-0003" and title "Child" with parent "cl-0001"
    And ticket "cl-0001" depends on "cl-0002"
    When I run "ticket close cl-0001 --reason done -m \"shipped\" --force"
    Then the exit code should be 0
    And the error output should contain "Warning: closing cl-0001 with open blockers: cl-0002"
    And the error output should contain "Warning: closing cl-0001 with open children: cl-0003"
    And ticket "cl-0001" should have field "status" with value "closed"
    And ticket "cl-0001" should contain "Closed: done - shipped"
    And ticket "cl-0001" should contain "Forced: open blockers cl-0002; open children cl-0003"

  Scenario: Force on a won't-do close records the dependents
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Dependent"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason wontdo -m \"out of scope\" --force"
    Then the exit code should be 0
    And the error output should contain "Warning: closing cl-0001 with open dependents: cl-0002"
    And ticket "cl-0001" should contain "Forced: open dependents cl-0002"

  Scenario: Force without violations writes no Forced line
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done -m \"shipped\" --force"
    And I run "ticket show cl-0001"
    Then the output should contain "Closed: done - shipped"
    And the output should not contain "Forced:"

  # --- Report ---

  Scenario: Unblocked dependents are reported, still blocked ones are not
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0002" and title "Becomes ready"
    And a ticket exists with ID "cl-0003" and title "Still blocked"
    And a ticket exists with ID "cl-0004" and title "Other blocker"
    And ticket "cl-0002" depends on "cl-0001"
    And ticket "cl-0003" depends on "cl-0001"
    And ticket "cl-0003" depends on "cl-0004"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the exit code should be 0
    And the output line 3 should contain "Now ready: cl-0002"
    And the output should not contain "cl-0003"

  Scenario: Several unblocked dependents are listed in ID order
    Given a ticket exists with ID "cl-0001" and title "Target"
    And a ticket exists with ID "cl-0003" and title "Second"
    And a ticket exists with ID "cl-0002" and title "First"
    And ticket "cl-0003" depends on "cl-0001"
    And ticket "cl-0002" depends on "cl-0001"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the output line 3 should contain "Now ready: cl-0002, cl-0003"

  Scenario: Nothing became ready
    Given a ticket exists with ID "cl-0001" and title "Target"
    When I run "ticket close cl-0001 --reason done -m \"shipped\""
    Then the output line 3 should contain "Nothing became ready"
    And the output line count should be 3

  Scenario: Parent hint when the last open child closes
    Given a ticket exists with ID "cl-0001" and title "Parent"
    And a ticket exists with ID "cl-0002" and title "Child" with parent "cl-0001"
    When I run "ticket close cl-0002 --reason done -m \"shipped\""
    Then the exit code should be 0
    And the output line 4 should contain "Last open child of cl-0001 closed - consider closing cl-0001"

  Scenario: No parent hint while a sibling is open
    Given a ticket exists with ID "cl-0001" and title "Parent"
    And a ticket exists with ID "cl-0002" and title "Child" with parent "cl-0001"
    And a ticket exists with ID "cl-0003" and title "Sibling" with parent "cl-0001"
    When I run "ticket close cl-0002 --reason done -m \"shipped\""
    Then the exit code should be 0
    And the output should not contain "Last open child"
