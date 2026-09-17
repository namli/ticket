Feature: Ticket Impact
  As a user or an agent
  I want to see what closing a ticket would change
  So that I never close a ticket without knowing its effect on the graph

  Background:
    Given a clean tickets directory

  # --- CLI: arguments, ID resolution, exit codes ---

  Scenario: Ticket with no relations has no impact
    Given a ticket exists with ID "imp-0001" and title "Lonely"
    When I run "ticket impact imp-0001"
    Then the exit code should be 0
    And the output line 1 should contain "imp-0001 [open] Lonely"
    And the output should contain "No impact: nothing depends on imp-0001"
    And the error output should be empty

  Scenario: Partial ID works
    Given a ticket exists with ID "imp-0001" and title "Lonely"
    When I run "ticket impact 0001"
    Then the exit code should be 0
    And the output line 1 should contain "imp-0001 [open] Lonely"

  Scenario: Ambiguous partial ID fails
    Given a ticket exists with ID "imp-0001" and title "First"
    And a ticket exists with ID "imp-0002" and title "Second"
    When I run "ticket impact imp-"
    Then the exit code should be 1
    And the error output should contain "ambiguous ID 'imp-' matches multiple tickets"
    And the output should be empty

  Scenario: Unknown ID fails
    Given a ticket exists with ID "imp-0001" and title "First"
    When I run "ticket impact nope"
    Then the exit code should be 1
    And the error output should contain "ticket 'nope' not found"

  Scenario: Missing ID prints usage
    When I run "ticket impact"
    Then the exit code should be 2
    And the error output should contain "Usage: tk impact [--porcelain] <id>"

  Scenario: Two IDs are rejected
    Given a ticket exists with ID "imp-0001" and title "First"
    And a ticket exists with ID "imp-0002" and title "Second"
    When I run "ticket impact imp-0001 imp-0002"
    Then the exit code should be 2
    And the error output should contain "only one ticket ID is accepted"

  Scenario: Unknown flag is rejected
    When I run "ticket impact --bogus imp-0001"
    Then the exit code should be 2
    And the error output should contain "Unknown option: --bogus"

  Scenario: No tickets directory is an environment error
    Given the tickets directory does not exist
    When I run "ticket impact imp-0001"
    Then the exit code should be 2
    And the error output should contain "no .tickets directory found"

  Scenario: Help prints usage
    When I run "ticket impact --help"
    Then the exit code should be 0
    And the output should contain "Usage: tk impact [--porcelain] <id>"

  Scenario: tk help lists the plugin
    When I run "ticket help"
    Then the command should succeed
    And the output should match pattern "impact\s+Show what closing a ticket would change"
