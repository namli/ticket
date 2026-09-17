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

  # --- Graph facts, human output ---

  Scenario: Dependent with a single blocker becomes ready
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Waiting"
    And ticket "imp-0002" depends on "imp-0001"
    When I run "ticket impact imp-0001"
    Then the exit code should be 0
    And the output should contain "Becomes ready:"
    And the output should contain "- imp-0002 [open] Waiting"
    And the output should not contain "Still blocked by others:"
    And the output should not contain "No impact"

  Scenario: Dependent with a second open blocker stays blocked
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Waiting"
    And a ticket exists with ID "imp-0003" and title "Other blocker"
    And ticket "imp-0002" depends on "imp-0001"
    And ticket "imp-0002" depends on "imp-0003"
    When I run "ticket impact imp-0001"
    Then the exit code should be 0
    And the output should contain "Still blocked by others:"
    And the output should contain "- imp-0002 [open] Waiting <- imp-0003"
    And the output should not contain "Becomes ready:"

  Scenario: Dependent whose other blocker is closed becomes ready
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Waiting"
    And a ticket exists with ID "imp-0003" and title "Other blocker"
    And ticket "imp-0002" depends on "imp-0001"
    And ticket "imp-0002" depends on "imp-0003"
    And ticket "imp-0003" has status "closed"
    When I run "ticket impact imp-0001"
    Then the output should contain "Becomes ready:"
    And the output should contain "- imp-0002 [open] Waiting"
    And the output should not contain "Still blocked by others:"

  Scenario: Closed dependents are ignored
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Finished"
    And ticket "imp-0002" depends on "imp-0001"
    And ticket "imp-0002" has status "closed"
    When I run "ticket impact imp-0001"
    Then the exit code should be 0
    And the output should contain "No impact: nothing depends on imp-0001"
    And the output should not contain "imp-0002"

  Scenario: Open children are listed and closed children are not
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Open child" with parent "imp-0001"
    And a ticket exists with ID "imp-0003" and title "Closed child" with parent "imp-0001"
    And ticket "imp-0003" has status "closed"
    When I run "ticket impact imp-0001"
    Then the output should contain "Open children:"
    And the output should contain "- imp-0002 [open] Open child"
    And the output should not contain "imp-0003"

  Scenario: Last open child of an open parent is reported
    Given a ticket exists with ID "imp-par" and title "Epic"
    And a ticket exists with ID "imp-0001" and title "Target" with parent "imp-par"
    And a ticket exists with ID "imp-0002" and title "Done sibling" with parent "imp-par"
    And ticket "imp-0002" has status "closed"
    When I run "ticket impact imp-0001"
    Then the output should contain "Last open child of imp-par [open] Epic - consider closing the parent"

  Scenario: Not the last child while a sibling is open
    Given a ticket exists with ID "imp-par" and title "Epic"
    And a ticket exists with ID "imp-0001" and title "Target" with parent "imp-par"
    And a ticket exists with ID "imp-0002" and title "Open sibling" with parent "imp-par"
    When I run "ticket impact imp-0001"
    Then the output should not contain "Last open child"
    And the output should contain "No impact: nothing depends on imp-0001"

  Scenario: No last-child hint when the parent is closed
    Given a ticket exists with ID "imp-par" and title "Epic"
    And ticket "imp-par" has status "closed"
    And a ticket exists with ID "imp-0001" and title "Target" with parent "imp-par"
    When I run "ticket impact imp-0001"
    Then the output should not contain "Last open child"

  Scenario: Open blockers of the target are listed
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Blocker"
    And a ticket exists with ID "imp-0003" and title "Resolved blocker"
    And ticket "imp-0003" has status "closed"
    And ticket "imp-0001" depends on "imp-0002"
    And ticket "imp-0001" depends on "imp-0003"
    When I run "ticket impact imp-0001"
    Then the output should contain "Open blockers:"
    And the output should contain "- imp-0002 [open] Blocker"
    And the output should not contain "imp-0003"

  Scenario: A dangling blocker is shown as missing
    Given a ticket exists with ID "imp-0001" and title "Target"
    And ticket "imp-0001" depends on "imp-gone"
    When I run "ticket impact imp-0001"
    Then the output should contain "Open blockers:"
    And the output should contain "- imp-gone [missing]"

  Scenario: A self-dependency is not a blocker
    Given a ticket exists with ID "imp-0001" and title "Target"
    And ticket "imp-0001" depends on "imp-0001"
    When I run "ticket impact imp-0001"
    Then the output should contain "No impact: nothing depends on imp-0001"

  Scenario: Closed target says what a reopen would re-block
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Waiting"
    And ticket "imp-0002" depends on "imp-0001"
    And ticket "imp-0001" has status "closed"
    When I run "ticket impact imp-0001"
    Then the exit code should be 0
    And the output line 1 should contain "imp-0001 [closed] Target"
    And the output should contain "Already closed. Reopening would re-block:"
    And the output should contain "- imp-0002 [open] Waiting"
    And the output should not contain "Becomes ready:"

  # --- Porcelain ---

  Scenario: Porcelain prints every fact kind in a fixed order
    Given a ticket exists with ID "imp-par" and title "Epic"
    And a ticket exists with ID "imp-0001" and title "Target" with parent "imp-par"
    And a ticket exists with ID "imp-0002" and title "Blocker"
    And a ticket exists with ID "imp-0003" and title "Child" with parent "imp-0001"
    And a ticket exists with ID "imp-0004" and title "Ready one"
    And a ticket exists with ID "imp-0005" and title "Blocked one"
    And a ticket exists with ID "imp-0006" and title "Other blocker"
    And ticket "imp-0001" depends on "imp-0002"
    And ticket "imp-0004" depends on "imp-0001"
    And ticket "imp-0005" depends on "imp-0001"
    And ticket "imp-0005" depends on "imp-0006"
    And ticket "imp-0005" depends on "imp-0002"
    When I run "ticket impact --porcelain imp-0001"
    Then the exit code should be 0
    And the output line 1 should contain "status open"
    And the output line 2 should contain "blocker imp-0002"
    And the output line 3 should contain "child imp-0003"
    And the output line 4 should contain "ready imp-0004"
    And the output line 5 should contain "blocked imp-0005 imp-0002,imp-0006"
    And the output line 6 should contain "last-child imp-par"
    And the output line count should be 6
    And the error output should be empty

  Scenario: Porcelain sorts facts by ID
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0003" and title "Created first"
    And a ticket exists with ID "imp-0002" and title "Created second"
    And ticket "imp-0003" depends on "imp-0001"
    And ticket "imp-0002" depends on "imp-0001"
    When I run "ticket impact --porcelain imp-0001"
    Then the output line 2 should contain "ready imp-0002"
    And the output line 3 should contain "ready imp-0003"
    And the output line count should be 3

  Scenario: Porcelain with no impact prints only the status
    Given a ticket exists with ID "imp-0001" and title "Lonely"
    When I run "ticket impact --porcelain imp-0001"
    Then the exit code should be 0
    And the output should be "status open"

  Scenario: Porcelain flag may follow the ID
    Given a ticket exists with ID "imp-0001" and title "Lonely"
    When I run "ticket impact imp-0001 --porcelain"
    Then the exit code should be 0
    And the output should be "status open"

  Scenario: Porcelain on a closed target keeps the ready lines
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Waiting"
    And ticket "imp-0002" depends on "imp-0001"
    And ticket "imp-0001" has status "closed"
    When I run "ticket impact --porcelain imp-0001"
    Then the output line 1 should contain "status closed"
    And the output line 2 should contain "ready imp-0002"
    And the output line count should be 2

  # --- Regression guards from the final review ---

  Scenario: IDs that look like equal numbers are different tickets
    Given a ticket exists with ID "100" and title "Target"
    And a ticket exists with ID "1e2" and title "Looks equal"
    And a ticket exists with ID "7" and title "Depends on the other"
    And ticket "7" depends on "1e2"
    When I run "ticket impact --porcelain 100"
    Then the exit code should be 0
    And the output should be "status open"

  Scenario: An in-progress dependent becomes ready
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Started"
    And ticket "imp-0002" depends on "imp-0001"
    And ticket "imp-0002" has status "in_progress"
    When I run "ticket impact imp-0001"
    Then the output should contain "Becomes ready:"
    And the output should contain "- imp-0002 [in_progress] Started"

  Scenario: A dependent is reported once and duplicate blockers collapse
    Given a ticket exists with ID "imp-0001" and title "Target"
    And a ticket exists with ID "imp-0002" and title "Waiting"
    And a ticket exists with ID "imp-0003" and title "Other blocker"
    And ticket "imp-0002" has raw field "deps" set to "[imp-0001, imp-0003, imp-0001, imp-0003]"
    When I run "ticket impact --porcelain imp-0001"
    Then the output line 1 should contain "status open"
    And the output line 2 should contain "blocked imp-0002 imp-0003"
    And the output should not contain "imp-0003,imp-0003"
    And the output line count should be 2
