Feature: Insured Plan Shopping on Individual market
  Background:
    Given bs4_consumer_flow feature is enabled
    Given the FAA feature configuration is enabled
    Given FAA no_coverage_tribe_details feature is enabled
    Given Individual has not signed up as an HBX user
    And Individual visits the Consumer portal during open enrollment
    When Individual creates a new HBX account
    Then Individual should see a successful sign up message
    And Individual sees Your Information page
    And the user registers as an individual
    
  Scenario: New user creates an account
    Given Individual clicks on the Continue button of the Account Setup page
    Then Individual sees form to enter personal information but doesn't fill it out completely
    Then Individual clicks on continue
    Then Individual continues through authorization and consent page
    Then Individual answers the questions of the Identity Verification page and clicks on submit

  Scenario: New user creates an account and forgets to check a box
    Given Individual clicks on the Continue button of the Account Setup page
    Then Individual sees form to enter personal information but doesn't check every box
    And Individual clicks on continue
    Then Individual should see the custom validity message

  Scenario: Consumer clicks the personal match page continue button with contact preference text
    Given EnrollRegistry contact_method_via_dropdown feature is disabled
    Given the Continue button is visible on Account Setup page
    And Individual clicks on the Continue button of the Family Information page
    And Individual sees form to enter personal information with invalid phone number
    And Individual selects contact text check box
    Then Individual clicks on continue
    Then Individual should see a custom validity message for invalid mobile phone

  Scenario: Consumer clicks the personal match page continue button without contact preference text
    Given EnrollRegistry contact_method_via_dropdown feature is disabled
    Given the Continue button is visible on Account Setup page
    And Individual clicks on the Continue button of the Family Information page
    And Individual sees form to enter personal information with invalid phone number
    Then Individual clicks on continue
    Then Individual should see a custom validity message for invalid mobile phone
