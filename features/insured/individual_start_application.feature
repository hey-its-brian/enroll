Feature: Individual Market Application - Start New Application

  Background:
    Given Individual has not signed up as an HBX user
    Given the FAA feature configuration is enabled
    Given bs4_consumer_flow feature is enabled
    Given qhp_application feature is enabled
    Given EnrollRegistry contact_method_via_dropdown feature is disabled
    When Individual visits the Consumer portal during open enrollment

  Scenario: User signs up - iap selection disabled
    Given the iap year selection feature is disabled
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
    Then Individual is on the QHP Family Information page

  Scenario: User signs up - iap selection enabled, in OE
    Given the iap year selection feature is enabled
    Given the date is within open enrollment
    And current hbx is under open enrollment
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
    Then Individual is on the QHP Year Selection page

  Scenario: User signs up - iap selection enabled, after OE
    Given the iap year selection feature is enabled
    Given the date is after open enrollment
    And current hbx is not under open enrollment
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
    Then Individual is on the QHP Family Information page
