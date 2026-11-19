Feature: Web board
  As the owner of several tk projects
  I want one local page with the tickets of all of them
  So that I see what is ready and what is blocked

  # --- Plugin, config, command line ---

  Scenario: tk help lists the plugin
    When I run "ticket help"
    Then the output should contain "web"
    And the output should contain "Local kanban board over several tk projects"

  Scenario: A missing config stops the server
    When I run "ticket web --config /nonexistent/web.toml"
    Then the exit code should be 1
    And the output should contain "/nonexistent/web.toml"
    And the output should contain "[[project]]"

  Scenario: A duplicate project name is a config error
    Given a web config:
      """
      [[project]]
      name = "same"
      path = "{dir}"

      [[project]]
      name = "same"
      path = "{dir}"
      """
    When I run "ticket web --config web.toml"
    Then the exit code should be 1
    And the output should contain "same"
    And the output should contain "web.toml"

  Scenario: A project name with a slash is a config error
    Given a web config:
      """
      [[project]]
      name = "a/b"
      path = "{dir}"
      """
    When I run "ticket web --config web.toml"
    Then the exit code should be 1
    And the output should contain "a/b"

  Scenario: A config without projects is a config error
    Given a web config:
      """
      port = 7420
      """
    When I run "ticket web --config web.toml"
    Then the exit code should be 1
    And the output should contain "[[project]]"

  Scenario: The server lists the configured projects
    Given a web project "alpha"
    And a web project "beta"
    And the web server is running
    When I GET "/"
    Then the response status should be 200
    And the response header "Content-Type" should be "text/html; charset=utf-8"
    And the response should contain "data-project=\"alpha\""
    And the response should contain "data-project=\"beta\""

  Scenario: The config path comes from TK_WEB_CONFIG
    Given a web project "alpha"
    And the web server is running with the config in TK_WEB_CONFIG
    When I GET "/"
    Then the response status should be 200

  Scenario: A foreign Host header is rejected
    Given a web project "alpha"
    And the web server is running
    When I GET "/" with header "Host: evil.example"
    Then the response status should be 403

  Scenario: The localhost Host header is accepted
    Given a web project "alpha"
    And the web server is running
    When I GET "/" with header "Host: localhost:<port>"
    Then the response status should be 200

  Scenario: An unknown path is not found
    Given a web project "alpha"
    And the web server is running
    When I GET "/nope"
    Then the response status should be 404

  Scenario: A busy port stops the second server
    Given a web project "alpha"
    And the web server is running
    When I start a second web server on the same port
    Then the exit code should be 1
    And the output should contain "cannot listen"

  # --- Board pages ---

  Scenario: Tickets sit in the column of their state
    Given the standard web projects
    And the web server is running
    When I GET "/"
    Then the response status should be 200
    And project "alpha" column "blocked" should list "a-0003"
    And project "alpha" column "ready" should list "a-0002, a-0001"
    And project "alpha" column "in_progress" should list "a-0004, a-0005"
    And project "alpha" column "closed" should list "a-0007, a-0008, a-0006"
    And the lane of project "alpha" should show "5 open"
    And the lane of project "beta" should show "1 open"
    And the response should contain "Blocked"
    And the response should contain "Ready"
    And the response should contain "In progress"
    And the response should contain "Closed"

  Scenario: A blocked ticket in progress carries a mark
    Given the standard web projects
    And the web server is running
    When I GET "/"
    Then card "alpha/a-0005" should have class "is-blocked"
    And card "alpha/a-0004" should not have class "is-blocked"

  Scenario: A card shows title, priority, type, tags, blockers and parent
    Given a web project "alpha"
    And web project "alpha" has tickets:
      | id     | title     | priority | type | tags   | deps          | parent |
      | a-0001 | Epic one  | 2        | epic |        |               |        |
      | a-0002 | Open high | 1        | bug  | ui api | a-0003 a-9999 | a-0001 |
      | a-0003 | Blocker   | 2        |      |        |               |        |
    And the web server is running
    When I GET "/"
    Then card "alpha/a-0002" should contain "a-0002"
    And card "alpha/a-0002" should contain "Open high"
    And card "alpha/a-0002" should contain "P1"
    And card "alpha/a-0002" should contain "bug"
    And card "alpha/a-0002" should contain "ui"
    And card "alpha/a-0002" should contain "api"
    And card "alpha/a-0002" should contain "a-0003"
    And card "alpha/a-0002" should contain "a-9999"
    And card "alpha/a-0002" should contain "a-0001"
    And card "alpha/a-0001" should contain "epic"
    And the response should contain "href=\"/p/alpha/a-0002\""

  Scenario: A closed dep is not shown as a blocker
    Given a web project "alpha"
    And web project "alpha" has tickets:
      | id     | title  | status | deps   |
      | a-0001 | Needs  | open   | a-0002 |
      | a-0002 | Done   | closed |        |
    And the web server is running
    When I GET "/"
    Then project "alpha" column "ready" should list "a-0001"
    And card "alpha/a-0001" should not contain "a-0002"

  Scenario: Two projects with the same ticket id both render
    Given the standard web projects
    And the web server is running
    When I GET "/"
    Then project "beta" column "ready" should list "a-0001"
    And the response should contain "href=\"/p/alpha/a-0001\""
    And the response should contain "href=\"/p/beta/a-0001\""
    And card "beta/a-0001" should contain "Beta first"

  Scenario: The flat view merges the projects
    Given the standard web projects
    And the web server is running
    When I GET "/?flat=1"
    Then the response status should be 200
    And column "blocked" should list "alpha/a-0003"
    And column "ready" should list "alpha/a-0002, beta/a-0001, alpha/a-0001"
    And column "in_progress" should list "alpha/a-0004, alpha/a-0005"
    And column "closed" should list "alpha/a-0007, alpha/a-0008, alpha/a-0006"
    And the response should not contain "class=\"lane\""
    And card "beta/a-0001" should contain "beta"
    And card "alpha/a-0002" should contain "alpha"

  Scenario: The project page shows one project
    Given the standard web projects
    And the web server is running
    When I GET "/p/alpha"
    Then the response status should be 200
    And project "alpha" column "ready" should list "a-0002, a-0001"
    And project "alpha" column "closed" should list "a-0007, a-0008, a-0006"
    And the response should not contain "Beta first"

  Scenario: An unknown project page is not found
    Given the standard web projects
    And the web server is running
    When I GET "/p/nope"
    Then the response status should be 404

  Scenario: The board shows the five newest closed tickets
    Given a web project "alpha"
    And web project "alpha" has 7 closed tickets
    And the web server is running
    When I GET "/"
    Then project "alpha" column "closed" should list "c-0007, c-0006, c-0005, c-0004, c-0003"
    And the response should contain "2 more"
    And the response should contain "href=\"/p/alpha\""
    And the lane of project "alpha" should show "0 open"
    When I GET "/p/alpha"
    Then project "alpha" column "closed" should list "c-0007, c-0006, c-0005, c-0004, c-0003, c-0002, c-0001"
    And the response should not contain " more<"

  Scenario: The flat view shows five closed tickets per project
    Given a web project "alpha"
    And web project "alpha" has 7 closed tickets
    And a web project "beta"
    And web project "beta" has 6 closed tickets
    And the web server is running
    When I GET "/?flat=1"
    Then column "closed" should list "alpha/c-0007, alpha/c-0006, beta/c-0006, alpha/c-0005, beta/c-0005, alpha/c-0004, beta/c-0004, alpha/c-0003, beta/c-0003, beta/c-0002"

  Scenario: The project page shows fifty closed tickets and a link to all
    Given a web project "alpha"
    And web project "alpha" has 52 closed tickets
    And the web server is running
    When I GET "/p/alpha"
    Then the response should contain "2 more"
    And the response should contain "href=\"/p/alpha?closed=all\""
    And the response should not contain "Closed 2<"
    And the response should contain "Closed 3<"
    When I GET "/p/alpha?closed=all"
    Then the response should contain "Closed 1<"
    And the response should not contain " more<"

  Scenario: A project without a tickets directory shows an error in its lane
    Given the standard web projects
    And a web project "gone" without a tickets directory
    And the web server is running
    When I GET "/"
    Then the response status should be 200
    And the lane of project "gone" should show an error containing ".tickets"
    And project "alpha" column "blocked" should list "a-0003"
    And the lane of project "alpha" should show no error

  Scenario: A project without tickets shows an empty lane
    Given a web project "empty"
    And the web server is running
    When I GET "/"
    Then project "empty" column "ready" should list ""
    And project "empty" column "closed" should list ""
    And the lane of project "empty" should show no error
    And the lane of project "empty" should show "0 open"

  Scenario: An unknown status goes to Ready with its name
    Given a web project "alpha"
    And web project "alpha" has tickets:
      | id     | title    | status |
      | a-0001 | Reviewed | review |
    And the web server is running
    When I GET "/"
    Then project "alpha" column "ready" should list "a-0001"
    And card "alpha/a-0001" should contain "review"

  Scenario: A change on disk shows up without a restart
    Given the standard web projects
    And the web server is running
    When I GET "/"
    Then the response should contain "Open low"
    When web ticket "alpha/a-0001" file has "Open low" replaced by "Renamed low"
    Then GET "/" should eventually contain "Renamed low"

  Scenario: A ticket closed on disk moves to Closed and unblocks its dependent
    Given the standard web projects
    And the web server is running
    When I GET "/"
    Then project "alpha" column "blocked" should list "a-0003"
    When web ticket "alpha/a-0001" file has "status: open" replaced by "status: closed"
    And I GET "/"
    Then project "alpha" column "blocked" should list ""
    And project "alpha" column "ready" should list "a-0002, a-0003"
    And card "alpha/a-0005" should not have class "is-blocked"

  Scenario: A Russian title renders unchanged
    Given a web project "alpha"
    And web project "alpha" has tickets:
      | id     | title          |
      | a-0001 | Починить поиск |
    And the web server is running
    When I GET "/"
    Then card "alpha/a-0001" should contain "Починить поиск"

  Scenario: HTML in a title is escaped
    Given a web project "alpha"
    And web project "alpha" has tickets:
      | id     | title                           |
      | a-0001 | <script>alert(1)</script> & co |
    And the web server is running
    When I GET "/"
    Then the response should contain "&lt;script&gt;alert(1)&lt;/script&gt; &amp; co"
    And the response should not contain "<script>alert(1)"

  Scenario: Files that do not parse become unparsable cards
    Given the standard web projects
    And web ticket "alpha/bad-0001" has raw bytes "fffe00ff"
    And web ticket "alpha/nofm-0001" has content:
      """
      just text
      """
    And the web server is running
    When I GET "/"
    Then the response status should be 200
    And the response should contain "bad-0001.md unparsable"
    And the response should contain "nofm-0001.md unparsable"
    And project "alpha" column "ready" should list "a-0002, a-0001"
    And project "alpha" column "blocked" should list "a-0003"

  # --- Ticket page ---

  Scenario: The ticket page shows the text of every section
    Given the web project with a full ticket
    And the web server is running
    When I GET "/p/alpha/a-0002"
    Then the response status should be 200
    And the response should contain "Full ticket"
    And the response should contain "The description text."
    And the response should contain "The design text."
    And the response should contain "The acceptance text."
    And the response should contain "Risks"
    And the response should contain "The risk text."
    And the response should contain "A note text."
    And the response should contain "2026-02-03T04:05:06Z"
    And the response should contain "in_progress"
    And the response should contain "feature"
    And the response should contain "P1"
    And the response should contain "namli"
    And the response should contain "href=\"/p/alpha/a-0002/edit\""

  Scenario: The ticket page lists parent, deps and links
    Given the web project with a full ticket
    And the web server is running
    When I GET "/p/alpha/a-0002"
    Then relation "parent" should list "a-0001"
    And relation "deps" should list "a-0003, a-9999"
    And relation "links" should list "a-0004"
    And relation "deps" should contain "closed"
    And relation "deps" should contain "missing"
    And relation "deps" should have no link to "a-9999"
    And the response should contain "href=\"/p/alpha/a-0003\""

  Scenario: The ticket page lists children and dependents
    Given the web project with a full ticket
    And the web server is running
    When I GET "/p/alpha/a-0001"
    Then relation "children" should list "a-0002"
    When I GET "/p/alpha/a-0003"
    Then relation "dependents" should list "a-0002"
    And relation "deps" should list ""

  Scenario: Text on the ticket page is escaped
    Given a web project "alpha"
    And web ticket "alpha/a-0001" has content:
      """
      ---
      id: a-0001
      status: open
      deps: []
      links: []
      created: 2026-01-01T00:00:00Z
      type: task
      priority: 2
      ---
      # Escape <b>me</b>

      Use <script>alert(2)</script> & more.
      """
    And the web server is running
    When I GET "/p/alpha/a-0001"
    Then the response should contain "Escape &lt;b&gt;me&lt;/b&gt;"
    And the response should contain "&lt;script&gt;alert(2)&lt;/script&gt; &amp; more."
    And the response should not contain "<script>alert(2)"

  Scenario Outline: A ticket page that does not exist is not found
    Given the web project with a full ticket
    And web ticket "alpha/nofm-0001" has content:
      """
      just text
      """
    And the web server is running
    When I GET "<path>"
    Then the response status should be 404

    Examples:
      | path                       |
      | /p/alpha/zzz               |
      | /p/nope/a-0001             |
      | /p/alpha/..%2Fweb.toml     |
      | /p/alpha/a-0002/extra      |
      | /p/alpha/nofm-0001         |
