Feature: Individual Verification Individual Page
  Background:
    Given bs4_consumer_flow feature is enabled
    And show_new_verifications_household_summary feature is enabled
    And a consumer exists
    And the consumer is logged in
    And consumer has successful ridp
    And the consumer has a verification with outstanding status
    And the consumer visits the verification tab

  Scenario: Consumer has an identity verification
    And EnrollRegistry show_identity_verification feature is enabled
    And the consumer selects a household member
    Then the consumer should see the Identity verification row

  Scenario Outline: Consumer has alive status
    And the alive_status feature is enabled
    And the consumer has a Alive Status verification with <status> status
    And the consumer selects a household member
    Then the consumer <should_see> see the Deceased verification row

    Examples:
    | status      | should_see |
    | verified    | should not |
    | outstanding | should     |

  Scenario: Consumer goes to the Verification Detail page from the Individual table
    And the consumer selects a household member
    When the consumer selects the verification for the member
    Then the consumer should see the verification detail page

  Scenario: Consumer presses the Back to Verifications button
    And the consumer selects a household member
    When the consumer presses the Back to Verifications button
    Then the consumer should see the verifications household summary page
    