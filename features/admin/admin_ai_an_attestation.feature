Feature: Admin attempts to view their American Indian or Alaska Native status

  Background:
    Given bs4_consumer_flow feature is enabled
    Given Hbx Admin exists
    When Hbx Admin logs on to the Hbx Portal

  Scenario: Admin creates a New User with American Indian or Alaska Native status with feature enabled
    Given the ai_an_self_attestation feature is enabled
    When admin navigates to new user who has attested to American Indian or Alaska Native tribe membership
    And admin navigates to the user's documents page
    Then admin should see an American Indian or Alaska Native status
    And admin clicks on the Actions dropdown for the American Indian Status
    Then admin should see only View History action available

  Scenario: Admin changes the American Indian or Alaska Native attestation of an existing user
    Given the ai_an_self_attestation feature is enabled
    When admin navigates to existing user who has not attested to American Indian or Alaska Native tribe membership
    And admin navigates to the user's families page
    And admin updates the user's American Indian or Alaska Native attestation
    And admin navigates to the user's documents page
    Then admin should see an American Indian or Alaska Native status
    And admin clicks on the Actions dropdown for the American Indian Status
    Then admin should see only View History action available

  Scenario: Admin adds a dependent with American Indian or Alaska Native status during the FAA process
    Given the ai_an_self_attestation feature is enabled
    When admin navigates to existing user who has attested to American Indian or Alaska Native tribe membership
    And FAA application exists in determined state
    And admin navigates to the user's applications page
    And admin accesses the user's financial assistance application
    And admin adds a dependent to the user's family
    And admin updates the dependent's American Indian or Alaska Native attestation
    And admin returns to the applications page
    And admin navigates to the user's documents page
    Then admin should see an American Indian or Alaska Native status
    And admin clicks on the Actions dropdown for the American Indian Status
    Then admin should see only View History action available
