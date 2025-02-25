Feature: Individual Verification Individual Page
  Background:
    Given bs4_consumer_flow feature is enabled
    And show_new_verifications_household_summary feature is enabled
    And a consumer exists
    And the consumer is logged in
    And consumer has successful ridp
    And the consumer has a verification with outstanding status
    And the consumer visits the verification tab
    And the consumer selects a household member

  Scenario: Consumer goes to the Verification Detail page from the Individual table
    When the consumer selects the verification for the member
    Then the consumer should see the verification detail page

  Scenario: Consumer presses the Back to Verifications button
    When the consumer presses the Back to Verifications button
    Then the consumer should see the verifications household summary page
    