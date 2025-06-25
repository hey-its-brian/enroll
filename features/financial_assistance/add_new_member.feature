Feature: User add's new dependent and submit form after filling required fields

  Scenario: Add a dependent with missing relationship.
    Given bs4_consumer_flow feature is disable
    Given the FAA feature configuration is enabled
    Given the date is within open enrollment
    When that the user is on FAA Household Info: Family Members page
    Then user clicks the Add New Person Button
    And user enters applicant name, ssn, gender and dob
    And user selects no for applicant's coverage requirement
    And user selects no for applicant's incarcerated status
    And user selects no for applicant's indian_tribe_member status
    And user selects yes for applicant's us_citizen status
    And user selects no for applicant's naturalized_citizen status
    And user clicks comfirm member
    Then form should not submit due to required relationship options popup
    And user fills in the missing relationship
    And user clicks comfirm member
    Then the applicant should have been created successfully

  Scenario: User should not see family relationship page
    Given bs4_consumer_flow feature is enabled
    Given the FAA feature configuration is enabled
    Given qhp_application feature is enabled
    And the user is on FAA Family Information page
    When user clicks continue to next step
    Then user should see income and coverage information page

  Scenario: Add dependent to faa family information page
    Given bs4_consumer_flow feature is enabled
    Given the FAA feature configuration is enabled
    Given qhp_application feature is enabled
    And the user is on FAA Family Information page
    When user clicks on add new member to household 
    And user completes the required fields
    Then the user should see the new member added to the household
    When user clicks continue to next step
    Then user should see family relationships page

  Scenario: Remove dependent from faa family information page
    Given bs4_consumer_flow feature is enabled
    Given the FAA feature configuration is enabled
    Given qhp_application feature is enabled
    And the user is on FAA Family Information page
    And more than one member exists in the household
    When user clicks on remove member from household 
    Then the user should see the new member removed from the household

  Scenario: Navigates from tax info to family information page
    Given bs4_consumer_flow feature is enabled
    Given qhp_application feature is enabled
    And the user is on FAA Family Information page
    When user clicks continue to next step
    And the user clicks on Add income and coverage info
    When the user clicks My Household section on the left navigation
    Then the user will navigate to the FAA Family Information page

  @broken
  Scenario: Application transition from draft to cancelled status
    Given bs4_consumer_flow feature is enabled
    Given qhp_application feature is enabled
    When the user is on FAA Family Information page
    And user returns to the applications page
    And the user clicks on Start New Application
    And user returns to the applications page
    Then user should see application in cancelled status
    When the user clicks on Start New Application
    And user returns to the applications page
    Then user should only see one application in draft status