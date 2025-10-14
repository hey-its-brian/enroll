Feature: Individual Market Application - Current Applications Page

  Background: Current Applications Page
    Given bs4_consumer_flow feature is enabled
    And the FAA feature configuration is enabled
    And Individual Market with open enrollment period exists
    And qhp_application feature is enabled
    And the qhp consumer is RIDP verified
    Given a Hbx admin with hbx_staff role exists
    When a Hbx admin logs on to Portal
    And Hbx Admin click Families link
    And Hbx Admin clicks on a family member

  Scenario: During Open Enrollment, No Previous/Prospective Applications
    Given the date is within open enrollment
    And current hbx is under open enrollment
    Then the admin selects 'Applications' from the sidebar
    Then the user should see the current applications page
    Then the user should not see a prospective year application
    Then the user should not see a prospective year application banner
    And the user clicks on the start application accordion
    Then the user should see the current during oe text
    Then the user should not see the current not during oe text
    Then the user should see the applicable year draft or no application card
    Then the user should see the previous year draft or no application card

  Scenario: During Open Enrollment, With Previous/Prospective Applications
    Given the date is within open enrollment
    And current hbx is under open enrollment
    And the qhp consumer has an existing determined application
    And the qhp consumer has an additional existing prospective application
    Then the admin selects 'Applications' from the sidebar
    Then the user should see the current applications page
    Then the user should not see a prospective year application
    Then the user should not see a prospective year application banner
    And the user clicks on the start application accordion
    Then the user should see the current during oe text
    Then the user should not see the current not during oe text
    Then the user should see the applicable year application card
    Then the user should see the previous year draft or no application card

  Scenario: Outside Open Enrollment, No Prospective or Previous Applications
    Given the date is after open enrollment
    And current hbx is not under open enrollment
    Then the admin selects 'Applications' from the sidebar
    Then the user should see the current applications page
    Then the user should not see a prospective year application
    Then the user should not see a prospective year application banner
    And the user clicks on the start application accordion
    Then the user should not see the current during oe text
    Then the user should see the current not during oe text
    Then the user should see the applicable year draft or no application card
    Then the user should see the previous year draft or no application card

  Scenario: Outside Open Enrollment, With Prospective and Applicable Year Applications
    Given the date is after open enrollment
    And current hbx is not under open enrollment
    And the qhp consumer has an existing determined application
    And the qhp consumer has an additional existing prospective application
    Then the admin selects 'Applications' from the sidebar
    Then the user should see the current applications page
    Then the user should see a prospective year application banner
    Then the user should see the prospective year application card
    Then the user should see the applicable year application card
    Then the user should see the previous year draft or no application card






