Feature: Guarded dep and undep
  As a user or an agent
  I want tk dep and tk undep to refuse broken graphs and record the reason
  So that the dependency graph stays true without manual follow-up steps

  Background:
    Given a clean tickets directory
    And a ticket exists with ID "guard-0001" and title "First"
    And a ticket exists with ID "guard-0002" and title "Second"
    And a ticket exists with ID "guard-0003" and title "Third"

  # --- Self-dependency ---

  Scenario: Self-dependency is rejected
    When I run "ticket dep guard-0001 guard-0001 --reason 'loop'"
    Then the exit code should be 1
    And the error output should contain "guard-0001 cannot depend on itself"
    And the error output should contain "tk super dep"
    And ticket "guard-0001" should contain "deps: []"
    And ticket "guard-0001" should not contain "Blocked by"

  Scenario: Self-dependency through a partial ID is rejected
    When I run "ticket dep guard-0001 0001 --reason 'loop'"
    Then the exit code should be 1
    And the error output should contain "guard-0001 cannot depend on itself"

  # --- Notes ---

  Scenario: dep writes the Blocked by note
    When I run "ticket dep guard-0001 guard-0002 --reason 'needs the parser'"
    Then the exit code should be 0
    And the output line 1 should contain "Added dependency: guard-0001 -> guard-0002"
    And the output line 2 should contain "Note: Blocked by guard-0002: needs the parser"
    And ticket "guard-0001" should contain "deps: [guard-0002]"
    And ticket "guard-0001" should contain "Blocked by guard-0002: needs the parser"
    And ticket "guard-0001" should contain a timestamp in notes

  Scenario: The note goes on the blocked ticket only
    When I run "ticket dep guard-0001 guard-0002 --reason 'needs the parser'"
    Then the exit code should be 0
    And ticket "guard-0002" should not contain "Blocked by"

  Scenario: --reason=<text> form
    When I run "ticket dep guard-0001 guard-0002 --reason='needs the parser'"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "Blocked by guard-0002: needs the parser"

  Scenario: Flags may come before the IDs
    When I run "ticket dep --reason 'needs the parser' guard-0001 guard-0002"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: [guard-0002]"
    And ticket "guard-0001" should contain "Blocked by guard-0002: needs the parser"

  Scenario: IDs after -- are taken literally
    When I run "ticket dep --no-note -- guard-0001 guard-0002"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: [guard-0002]"

  Scenario: dep --no-note adds the dependency without a note
    When I run "ticket dep guard-0001 guard-0002 --no-note"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: [guard-0002]"
    And ticket "guard-0001" should not contain "Blocked by"
    And the output should not contain "Note:"

  Scenario: undep writes the No longer blocked by note
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket undep guard-0001 guard-0002 --reason 'split out'"
    Then the exit code should be 0
    And the output line 1 should contain "Removed dependency: guard-0001 -/-> guard-0002"
    And the output line 2 should contain "Note: No longer blocked by guard-0002: split out"
    And ticket "guard-0001" should contain "deps: []"
    And ticket "guard-0001" should contain "No longer blocked by guard-0002: split out"

  Scenario: undep --no-note removes the dependency without a note
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket undep guard-0001 guard-0002 --no-note"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: []"
    And ticket "guard-0001" should not contain "No longer blocked by"

  # --- Usage errors ---

  Scenario: dep without --reason is a usage error
    When I run "ticket dep guard-0001 guard-0002"
    Then the exit code should be 2
    And the error output should contain "--reason <text> is required"
    And the error output should contain "Usage: tk dep"
    And ticket "guard-0001" should contain "deps: []"

  Scenario: undep without --reason is a usage error
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket undep guard-0001 guard-0002"
    Then the exit code should be 2
    And the error output should contain "--reason <text> is required"
    And the error output should contain "Usage: tk undep"
    And ticket "guard-0001" should contain "deps: [guard-0002]"

  Scenario: --reason with --no-note is a usage error
    When I run "ticket dep guard-0001 guard-0002 --reason 'x' --no-note"
    Then the exit code should be 2
    And the error output should contain "mutually exclusive"
    And ticket "guard-0001" should contain "deps: []"

  Scenario: Empty reason is a usage error
    When I run "ticket dep guard-0001 guard-0002 --reason ''"
    Then the exit code should be 2
    And the error output should contain "--reason must not be empty"
    And ticket "guard-0001" should contain "deps: []"

  Scenario: Unknown option is a usage error
    When I run "ticket dep guard-0001 guard-0002 --force"
    Then the exit code should be 2
    And the error output should contain "unknown option: --force"
    And ticket "guard-0001" should contain "deps: []"

  Scenario: One ID only is a usage error
    When I run "ticket dep guard-0001 --no-note"
    Then the exit code should be 2
    And the error output should contain "expected <id> and <dep-id>"

  Scenario: --help prints usage for the invoked command
    When I run "ticket undep --help"
    Then the exit code should be 0
    And the output should contain "Usage: tk undep"
    And the output should contain "tk super undep"

  # --- Existing state ---

  Scenario: Duplicate dependency is reported and gets no second note
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket dep guard-0001 guard-0002 --reason 'again'"
    Then the exit code should be 0
    And the output should contain "Dependency already exists"
    And ticket "guard-0001" should contain "deps: [guard-0002]"
    And ticket "guard-0001" should not contain "Blocked by"

  Scenario: undep of an absent dependency fails without a note
    When I run "ticket undep guard-0001 guard-0002 --reason 'gone'"
    Then the exit code should be 1
    And the output should contain "Dependency not found"
    And ticket "guard-0001" should not contain "No longer blocked by"

  Scenario: A dependency whose ID is a substring of an existing one is not mistaken for it
    Given a ticket exists with ID "abc-001" and title "Short"
    And a ticket exists with ID "abc-0012" and title "Long"
    And ticket "guard-0001" depends on "abc-0012"
    When I run "ticket dep guard-0001 abc-001 --reason 'needs short'"
    Then the exit code should be 1
    And the error output should contain "did not add abc-001 to guard-0001"
    And the output should not contain "Dependency already exists"
    And ticket "guard-0001" should contain "deps: [abc-0012]"
    And ticket "guard-0001" should not contain "Blocked by"

  # --- IDs ---

  Scenario: Partial IDs resolve to full IDs
    When I run "ticket dep 0001 0002 --reason 'needs the parser'"
    Then the exit code should be 0
    And the output should contain "Added dependency: guard-0001 -> guard-0002"
    And ticket "guard-0001" should contain "Blocked by guard-0002: needs the parser"

  Scenario: Nonexistent ticket
    When I run "ticket dep guard-0001 nonexistent --no-note"
    Then the exit code should be 1
    And the error output should contain "Error: ticket 'nonexistent' not found"

  Scenario: Ambiguous ticket
    When I run "ticket dep guard-0001 guard- --no-note"
    Then the exit code should be 1
    And the error output should contain "Error: ambiguous ID 'guard-' matches multiple tickets"

  # --- Pass-through and bypass ---

  Scenario: dep tree works through the plugin
    Given ticket "guard-0001" depends on "guard-0002"
    When I run "ticket dep tree guard-0001"
    Then the exit code should be 0
    And the output should contain "guard-0001"
    And the output should contain "guard-0002"

  Scenario: dep cycle works through the plugin
    When I run "ticket dep cycle"
    Then the exit code should be 0
    And the output should contain "No dependency cycles found"

  Scenario: tk super dep bypasses the guard
    When I run "ticket super dep guard-0001 guard-0001"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: [guard-0001]"

  # --- Cycles ---

  Scenario: Two-node cycle is rejected
    Given ticket "guard-0002" depends on "guard-0001"
    When I run "ticket dep guard-0001 guard-0002 --reason 'loop'"
    Then the exit code should be 1
    And the error output should contain "guard-0001 -> guard-0002 would create a cycle: guard-0001 -> guard-0002 -> guard-0001"
    And the error output should contain "tk super dep"
    And ticket "guard-0001" should contain "deps: []"
    And ticket "guard-0001" should not contain "Blocked by"

  Scenario: Three-node cycle is rejected
    Given ticket "guard-0002" depends on "guard-0003"
    And ticket "guard-0003" depends on "guard-0001"
    When I run "ticket dep guard-0001 guard-0002 --reason 'loop'"
    Then the exit code should be 1
    And the error output should contain "would create a cycle: guard-0001 -> guard-0002 -> guard-0003 -> guard-0001"
    And ticket "guard-0001" should contain "deps: []"
    And ticket "guard-0001" should not contain "Blocked by"

  Scenario: A cycle through a closed ticket is rejected
    Given ticket "guard-0002" depends on "guard-0003"
    And ticket "guard-0003" depends on "guard-0001"
    And ticket "guard-0003" has status "closed"
    When I run "ticket dep guard-0001 guard-0002 --reason 'loop'"
    Then the exit code should be 1
    And the error output should contain "would create a cycle"
    And ticket "guard-0001" should contain "deps: []"

  Scenario: A diamond is not a cycle
    Given a ticket exists with ID "guard-0004" and title "Fourth"
    And ticket "guard-0001" depends on "guard-0002"
    And ticket "guard-0001" depends on "guard-0003"
    And ticket "guard-0002" depends on "guard-0004"
    When I run "ticket dep guard-0003 guard-0004 --reason 'shared base'"
    Then the exit code should be 0
    And ticket "guard-0003" should contain "deps: [guard-0004]"

  Scenario: A dependency on a missing ticket file does not break the walk
    Given ticket "guard-0002" has raw field "deps" set to "[ghost-9999]"
    When I run "ticket dep guard-0001 guard-0002 --no-note"
    Then the exit code should be 0
    And ticket "guard-0001" should contain "deps: [guard-0002]"
