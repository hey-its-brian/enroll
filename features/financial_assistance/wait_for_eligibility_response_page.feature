Feature: The page that appears while the user is waiting for eligibility results to be returned

  Scenario: User is waiting for eligibility results
    Given bs4_consumer_flow feature is disable
    Given the FAA feature configuration is enabled
    And the user is on FAA Household Info: Family Members page
    And primary applicant is in Info Completed state
    And the user clicks CONTINUE
    And the user is on the Review Your Application page
    And the user clicks CONTINUE
    Then the user is on the Your Preferences page
    When the user clicks CONTINUE
    Then the user is on the Submit Your Application page
    Given all required questions are answered
    And the user has signed their name
    And the submit button will be enabled
    And the user clicks SUBMIT
    Then the user should see the waiting for eligibility results page

  Scenario: BS4 and QHP enabled User is waiting for eligibility results
    Given bs4_consumer_flow feature is enabled
    Given qhp_application feature is enabled
    Given the FAA feature configuration is enabled
    And the user is on FAA Family Information page
    And user clicks continue to next step
    And primary applicant is in Info Completed state
    And user clicks on Continue to next step button
    And the user is on the Your Preferences page
    And user clicks on Continue to next step button
    Then the user is on the Review Your Application page
    And user clicks on Continue to next step button
    Then the user is on the Submit Your Application page
    Given all required questions are answered
    And the user has signed their name
    And the submit button will be enabled
    And the user clicks SUBMIT
    Then the user should see the waiting for eligibility results page
