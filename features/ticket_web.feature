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
