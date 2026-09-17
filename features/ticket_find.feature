Feature: Ticket Find
  As a user or an agent
  I want to search ticket content in one command
  So that I find related tickets before creating a duplicate

  Background:
    Given a clean tickets directory

  Scenario: Match in the title
    Given a ticket exists with ID "find-0001" and title "Fix login redirect"
    And a ticket exists with ID "find-0002" and title "Add export button"
    When I run "ticket find login"
    Then the exit code should be 0
    And the output should be "find-0001 [P2][open] - Fix login redirect"

  Scenario: Match in the body
    Given a ticket exists with ID "find-0001" and title "First"
    And a ticket exists with ID "find-0002" and title "Second"
    And ticket "find-0002" has body line "Touches src/Auth/SessionStore.php"
    When I run "ticket find SessionStore"
    Then the exit code should be 0
    And the output should be "find-0002 [P2][open] - Second"

  Scenario: Match in the notes
    Given a ticket exists with ID "find-0001" and title "First"
    And a ticket exists with ID "find-0002" and title "Second"
    And ticket "find-0001" has a note "Blocked by the flaky importer"
    When I run "ticket find importer"
    Then the exit code should be 0
    And the output should be "find-0001 [P2][open] - First"

  Scenario: Matching is case-insensitive
    Given a ticket exists with ID "find-0001" and title "Fix Login Redirect"
    When I run "ticket find LOGIN"
    Then the exit code should be 0
    And the output should contain "find-0001"

  Scenario: Pattern is an extended regex
    Given a ticket exists with ID "find-0001" and title "Rename colour picker"
    And a ticket exists with ID "find-0002" and title "Rename color palette"
    And a ticket exists with ID "find-0003" and title "Rename font picker"
    When I run "ticket find 'colou?r'"
    Then the exit code should be 0
    And the output should contain "find-0001"
    And the output should contain "find-0002"
    And the output should not contain "find-0003"

  Scenario: A ticket matching on several lines is listed once
    Given a ticket exists with ID "find-0001" and title "Cache warmup"
    And ticket "find-0001" has body line "The cache is cold after deploy"
    And ticket "find-0001" has a note "Cache key must include the locale"
    When I run "ticket find cache"
    Then the exit code should be 0
    And the output line count should be 1

  Scenario: Front matter is not searched
    Given a ticket exists with ID "find-0001" and title "First"
    When I run "ticket find task"
    Then the exit code should be 1
    And the output should be empty
    And the error output should be empty

  Scenario: Priority and status are shown
    Given a ticket exists with ID "find-0001" and title "Urgent login fix" with priority 0
    And ticket "find-0001" has status "in_progress"
    When I run "ticket find login"
    Then the exit code should be 0
    And the output should be "find-0001 [P0][in_progress] - Urgent login fix"

  Scenario: Closed tickets are excluded by default
    Given a ticket exists with ID "find-0001" and title "Old login bug"
    And a ticket exists with ID "find-0002" and title "New login bug"
    And ticket "find-0001" has status "closed"
    When I run "ticket find login"
    Then the exit code should be 0
    And the output should contain "find-0002"
    And the output should not contain "find-0001"

  Scenario: Only closed tickets match without --all
    Given a ticket exists with ID "find-0001" and title "Old login bug"
    And ticket "find-0001" has status "closed"
    When I run "ticket find login"
    Then the exit code should be 1
    And the output should be empty
    And the error output should be empty

  Scenario: Closed tickets are included with --all
    Given a ticket exists with ID "find-0001" and title "Old login bug"
    And a ticket exists with ID "find-0002" and title "New login bug"
    And ticket "find-0001" has status "closed"
    When I run "ticket find --all login"
    Then the exit code should be 0
    And the output should contain "find-0001 [P2][closed] - Old login bug"
    And the output should contain "find-0002"

  Scenario: Multiple patterns are OR-ed
    Given a ticket exists with ID "find-0001" and title "Fix login redirect"
    And a ticket exists with ID "find-0002" and title "Add export button"
    And a ticket exists with ID "find-0003" and title "Update footer"
    When I run "ticket find login export"
    Then the exit code should be 0
    And the output should contain "find-0001"
    And the output should contain "find-0002"
    And the output should not contain "find-0003"

  Scenario: Tag filter with -T
    Given a ticket exists with ID "find-0001" and title "Login form layout"
    And a ticket exists with ID "find-0002" and title "Login token expiry"
    And ticket "find-0001" has raw field "tags" set to "[ui, forms]"
    And ticket "find-0002" has raw field "tags" set to "[backend]"
    When I run "ticket find -T ui login"
    Then the exit code should be 0
    And the output should be "find-0001 [P2][open] - Login form layout"

  Scenario: Tag filter with --tag
    Given a ticket exists with ID "find-0001" and title "Login form layout"
    And a ticket exists with ID "find-0002" and title "Login token expiry"
    And ticket "find-0001" has raw field "tags" set to "[ui, forms]"
    And ticket "find-0002" has raw field "tags" set to "[backend]"
    When I run "ticket find login --tag=backend"
    Then the exit code should be 0
    And the output should be "find-0002 [P2][open] - Login token expiry"

  Scenario: Tag filter matches whole tags only
    Given a ticket exists with ID "find-0001" and title "Login form layout"
    And ticket "find-0001" has raw field "tags" set to "[ui-kit]"
    When I run "ticket find -T ui login"
    Then the exit code should be 1
    And the output should be empty
    And the error output should be empty

  Scenario: No match exits 1
    Given a ticket exists with ID "find-0001" and title "First"
    When I run "ticket find nonexistent"
    Then the exit code should be 1
    And the output should be empty
    And the error output should be empty

  Scenario: Empty tickets directory exits 1
    When I run "ticket find anything"
    Then the exit code should be 1
    And the output should be empty
    And the error output should be empty

  Scenario: Missing pattern is a usage error
    Given a ticket exists with ID "find-0001" and title "First"
    When I run "ticket find"
    Then the exit code should be 2
    And the output should be empty
    And the error output should contain "Usage: tk find"

  Scenario: Unknown option is a usage error
    Given a ticket exists with ID "find-0001" and title "First"
    When I run "ticket find --bogus login"
    Then the exit code should be 2
    And the error output should contain "unknown option"

  Scenario: Pattern starting with a dash after --
    Given a ticket exists with ID "find-0001" and title "Support --force flag"
    When I run "ticket find -- --force"
    Then the exit code should be 0
    And the output should contain "find-0001"
