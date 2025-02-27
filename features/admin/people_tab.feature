Feature: Persons tab

  Background:
    Given EnrollRegistry people_tab feature is enabled
    Given EnrollRegistry bs4_admin_flow feature is enabled

  Scenario: Admin should see the persons table
    Given Hbx Admin exists
    When Hbx Admin logs on to the Hbx Portal
    And user visits the HBX Portal
    When Hbx Admin navigates to the People tab
    Then the Hbx Admin should see the People title    
    Then the Hbx Admin should see the name, dob, hbx id, roles, and actions columns

  Scenario: Admin should see not see filter and export options
    Given Hbx Admin exists
    When Hbx Admin logs on to the Hbx Portal
    And user visits the HBX Portal
    When Hbx Admin navigates to the People tab
    Then the Hbx Admin should not see filter options
    And the Hbx Admin should not see export options

  Scenario Outline: Admin should see consumer role in the role column
    Given Hbx Admin exists
    When Hbx Admin logs on to the Hbx Portal
    And user visits the HBX Portal
    And that a user with a <role> exists and is not logged in
    And Hbx Admin navigates to the People tab
    Then the Hbx Admin will see <user_facing_role> role in the role column

    Examples:
      | role                                  | user_facing_role    |
      | Consumer role                         | Consumer            |
      | Broker role                           | Broker Agency Staff |
      | HBX staff role with HBX staff subrole | HBX Staff           |

  Scenario Outline: Admin should see person when searching by criteria
    Given Hbx Admin exists
    When Hbx Admin logs on to the Hbx Portal
    And user visits the HBX Portal
    And that a person exists with <field> as <value>
    And Hbx Admin navigates to the People tab
    When the Hbx searches by <value>
    Then the Hbx Admin will see the user

    Examples:
      | field       | value       |
      | ssn         | 123121234   |
      | hbx id      | 5000081     |

  Scenario: Admin should see actions column
    And a Hbx admin with read only permissions exists
    And a consumer without a family exists
    And Hbx Admin logs on to the Hbx Portal
    And user visits the HBX Portal
    And Hbx Admin navigates to the People tab
    Then the Hbx Admin should see no actions for the consumer
    