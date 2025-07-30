Feature: Insured QHP Family Information Page

  Background:
    Given Individual has not signed up as an HBX user
    Given EnrollRegistry contact_method_via_dropdown feature is disabled
    Given the FAA feature configuration is enabled
    Given bs4_consumer_flow feature is enabled
    Given qhp_application feature is enabled
    When Individual visits the Consumer portal during open enrollment
    Then Individual creates a new HBX account
    Then Individual should see a successful sign up message
    And Individual sees Your Information page
    When user registers as an individual
    When individual clicks on the Continue button of the Account Setup page
    And Individual sees form to enter personal information
    When the individual clicks continue on the personal information page
    And Individual agrees to the privacy agreeement
    And the person named Patrick Doe is RIDP verified
    And Individual answers the questions of the Identity Verification page and clicks on submit
    Then Individual is on the Help Paying for Coverage page
    When Individual does not apply for assistance and clicks continue

  Scenario: New insured user navigates to QHP familly information page 
    Then Individual is on the QHP Family Information page
    
  Scenario: New insured user navigates to QHP prefrences page   
    When Individual clicks on continue to next step
    Then Individual is on the QHP Preferences page

  Scenario: New insured user submits QHP application
    When Individual clicks on continue to next step on QHP Family Information page
    And Individual clicks on continue to next step on QHP Preferences page
    And Individual clicks on continue to next step on QHP Review page
    And Individual agrees and submits QHP application
    