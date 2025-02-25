Feature: Individual Verifications Page
  Background:
    Given bs4_consumer_flow feature is enabled
    And a consumer exists
    And the consumer is logged in
    And consumer has successful ridp

  Scenario: Consumer goes to the Documents page while show_new_verifications_household_summary is enabled
    Given show_new_verifications_household_summary feature is enabled
    When the consumer visits the verification tab
    Then the consumer should see the verifications household summary page

  Scenario: Consumer goes to the Documents page while show_new_verifications_household_summary is disabled
    Given show_new_verifications_household_summary feature is disabled
    When the consumer visits the verification tab
    Then the consumer should see the old verifications documents page

  Scenario Outline: Consumer goes to the Documents page with verifications of statuses
    Given show_new_verifications_household_summary feature is enabled
    And the consumer has a verification with <status> status
    When the consumer visits the verification tab
    Then the consumer should <see_or_not_see> a <status> item in the Action Items table
    And the consumer should <see_or_not_see> an outstanding member in the Household Members table <with_or_without_date> date

    Examples:
      | status       | see_or_not_see | with_or_without_date |
      | outstanding  | see            | with                 |
      | rejected     | see            | with                 |
      | review       | not see        | with                 |
      | pending      | not see        | without              |
      | verified     | not see        | without              |
      | attested     | not see        | without              |
      | curam        | not see        | without              | 

  Scenario: Consumer goes to the Verification Detail page from the Action Items table
    Given show_new_verifications_household_summary feature is enabled
    And the consumer has a verification with outstanding status
    And the consumer visits the verification tab
    When the consumer selects the action item for the actionable verification
    Then the consumer should see the verification detail page

  Scenario: Consumer goes to the Individual Detail page from the Household Members table
    Given show_new_verifications_household_summary feature is enabled
    And the consumer visits the verification tab
    And the consumer selects a household member
    Then the consumer should see the individual detail page
