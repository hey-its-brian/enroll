Feature: Consumer My Expert page

  Background: Consumer has an Expert selected and visits the home page
    Given bs4_consumer_flow feature is enabled
    And a consumer exists
    And an individual market broker exists
    And a consumer role family exists with broker
    And the consumer is logged in
    And consumer has successful ridp
    And consumer visits home page

  Scenario: Consumer sees correct consumer navigation pane
    Then the consumer should see Expert page navigation link

  Scenario: Consumer sees Help with Plan Shopping modal
    When the consumer goes to the Expert page
    When the the consumer selects Select an Assister button
    Then the consumer should see the Help with Plan Shopping modal
    