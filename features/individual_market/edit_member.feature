Feature: User edits existing applicant on a qhp application

  Background: User has existing qhp application
    Given bs4_consumer_flow feature is enabled
    And the FAA feature configuration is enabled
    And the date is within open enrollment
    And qhp_application feature is enabled
    And AI AN Details feature is enabled
    And the qhp consumer has an existing determined application
    And the qhp consumer is RIDP verified
    And the qhp consumer is logged in
    And the qhp consumer navigates to 'update application'
    Then user should see an 'edit' option for each applicant
  
  Scenario Outline: User edits applicant info
    When the user clicks the edit <role> qhp applicant button
    And the user updates the <field> of the <role> qhp applicant to <value>
    And user clicks save changes on the qhp application
    Then the user should see <value> in the <role> applicant <field> field

  Examples:
    | role      | field         | value              |
    | primary   | first_name    | Barry              |
    | dependent | first_name    | Barry              |
    | primary   | last_name     | Smith              |
    | dependent | last_name     | Smith              |
    | primary   | gender        | Female             |
    | dependent | gender        | Male               |
    | primary   | dob           | 19                 |
    | dependent | dob           | 19                 |
    | dependent | relationship  | domestic_partner   |
