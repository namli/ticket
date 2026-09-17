Feature: Ticket Lint
  As a user or an agent
  I want to check every ticket for broken invariants in one command
  So that a damaged dependency graph is caught before it is committed

  Background:
    Given a clean tickets directory

  # --- Basics: exit codes and field rules ---

  Scenario: Clean repository prints nothing
    Given a ticket exists with ID "lint-0001" and title "First"
    And a ticket exists with ID "lint-0002" and title "Second"
    And ticket "lint-0002" depends on "lint-0001"
    And ticket "lint-0001" is linked to "lint-0002"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be empty
    And the error output should be empty

  Scenario: Empty tickets directory is clean
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be empty

  Scenario: Unknown option is a usage error
    Given a ticket exists with ID "lint-0001" and title "First"
    When I run "ticket lint --bogus"
    Then the exit code should be 2
    And the error output should contain "Unknown option: --bogus"

  Scenario: No tickets directory is an environment error
    Given the tickets directory does not exist
    When I run "ticket lint"
    Then the exit code should be 2
    And the error output should contain "no .tickets directory found"

  Scenario: A horizontal rule in the body is not front matter
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has body line "---"
    And ticket "lint-0001" has body line "status: bogus"
    And ticket "lint-0001" has body line "---"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should be empty

  Scenario: id field differs from the file name
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has raw field "id" set to "other-9999"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should contain ".tickets/lint-0001.md:2: error:"
    And the output should contain "[id-mismatch]"

  Scenario: id field is missing
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has no field "id"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should contain ".tickets/lint-0001.md:1: error: missing id field [id-mismatch]"

  Scenario: Invalid status is reported even on a ticket that is not open
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has raw field "status" set to "done"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should contain ".tickets/lint-0001.md:3: error:"
    And the output should contain "[invalid-status]"

  Scenario: Invalid priority
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has raw field "priority" set to "high"
    When I run "ticket lint"
    Then the exit code should be 1
    And the output should contain ".tickets/lint-0001.md:8: error:"
    And the output should contain "[invalid-priority]"

  Scenario: Unknown type is only a warning
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has raw field "type" set to "spike"
    When I run "ticket lint"
    Then the exit code should be 0
    And the output should contain ".tickets/lint-0001.md:7: warning:"
    And the output should contain "[invalid-type]"
    And the error output should contain "0 errors, 1 warning"

  Scenario: Strict mode fails on warnings
    Given a ticket exists with ID "lint-0001" and title "First"
    And ticket "lint-0001" has raw field "type" set to "spike"
    When I run "ticket lint --strict"
    Then the exit code should be 1
    And the output should contain "[invalid-type]"
