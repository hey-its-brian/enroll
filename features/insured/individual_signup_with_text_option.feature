Feature: Individual Sign Up

  Background:
    Given bs4_consumer_flow feature is enabled
    Given EnrollRegistry contact_method_via_dropdown feature is disabled
    Given the FAA feature configuration is enabled
    Given Individual has not signed up as an HBX user
    And Individual visits the Consumer portal during open enrollment
  
  Scenario: New user enters text only contact method
    When Individual creates a new HBX account
    Then Individual should see a successful sign up message
    And Individual sees Your Information page
    When user registers as an individual
    And Individual clicks on the Continue button of the Account Setup page
    Then Individual sees form to enter personal information
		And Individual selects text option
    And Individual clicks on continue
		And Individual selects mail option
		And Individual clicks on continue
		Then Individual lands on the authorization and consent page
