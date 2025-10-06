Feature: User adds new dependent to a qhp application

  Scenario: Add a dependent with missing relationship to a qhp application
    Given bs4_consumer_flow feature is enabled
    Given the FAA feature configuration is enabled
    Given the date is within open enrollment
    Given qhp_application feature is enabled
    Given the date is after open enrollment
    And AI AN Details feature is enabled
    When the user is eligible for a qhp application
    Given the user opts out of IAP
    Then user clicks the Add Member to Household button
    And user enters qhp applicant name, ssn, gender and dob
    And user selects yes for qhp applicant's coverage requirement
    And user selects no for qhp applicant's incarcerated status
    And user selects no for qhp applicant's indian_tribe_member status
    And user selects yes for qhp applicant's us_citizen status
    And user selects no for qhp applicant's naturalized_citizen status
    And user clicks confirm member on the qhp application
    Then qhp applicant form should not create a new applicant due to required relationship
    And user fills in the missing qhp relationship
    And user clicks confirm member on the qhp application
    Then the qhp applicant should have been created successfully

  Scenario: User should see the contact preferences page after continuing
    Given bs4_consumer_flow feature is enabled
    Given the FAA feature configuration is enabled
    Given qhp_application feature is enabled
    And the user is eligible for a qhp application
    Given the user opts out of IAP
    When user clicks continue to next step
    Then user should see contact preferences page
