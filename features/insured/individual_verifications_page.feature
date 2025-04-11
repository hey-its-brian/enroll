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

  Scenario Outline: Consumer goes to the Documents page with varying verifications
    Given show_new_verifications_household_summary feature is enabled
    And the consumer has these verifications:
      | Type         | Status        |
      | <type_1>     | <status_1>    |
      | <type_2>     | <status_2>    |
    When the consumer visits the verification tab
    Then the consumer should have <action_items_count> items in the Action Items table
    And the consumer should see a household member with <cumulative_status> status <with_or_without_date> date <with_or_without_warning>

  Examples:
    | type_1                 | status_1    | type_2                 | status_2    | action_items_count | cumulative_status | with_or_without_date | with_or_without_warning |
    # Single verification scenarios
    | Citizenship            | outstanding | none                   | none        | 1                  | Unverified        | with                 | with warning            |
    | Citizenship            | rejected    | none                   | none        | 1                  | Unverified        | with                 | with warning            |
    | Citizenship            | review      | none                   | none        | 0                  | Review            | with                 | without warning         |
    | Citizenship            | pending     | none                   | none        | 0                  | Verified          | without              | without warning         |
    | Citizenship            | verified    | none                   | none        | 0                  | Verified          | without              | without warning         |
    | Citizenship            | attested    | none                   | none        | 0                  | Verified          | without              | without warning         |
    | Citizenship            | curam       | none                   | none        | 0                  | Verified          | without              | without warning         |
    # Multiple verification scenarios
    | Citizenship            | review      | Social Security Number | review      | 0                  | Review            | with                 | without warning         |
    | Citizenship            | review      | Social Security Number | verified    | 0                  | Review            | with                 | without warning         |
    | Citizenship            | review      | Social Security Number | outstanding | 1                  | Unverified        | with                 | with warning            |
    | Citizenship            | verified    | Social Security Number | verified    | 0                  | Verified          | without              | without warning         |
    | Citizenship            | outstanding | Social Security Number | verified    | 1                  | Unverified        | with                 | with warning            |
    | Citizenship            | outstanding | Social Security Number | review      | 1                  | Unverified        | with                 | with warning            |
    | Citizenship            | outstanding | Social Security Number | rejected    | 2                  | Unverified        | with                 | with warning            |
    | Social Security Number | pending     | Immigration status     | review      | 0                  | Review            | with                 | without warning         |

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

  Scenario: Consumer goes to the Documents page with inactive members
    Given show_new_verifications_household_summary feature is enabled
    And EnrollRegistry show_inactive_verification_members feature is disabled
    And the consumer has an inactive family member
    And the determination for the family has been built
    And the consumer visits the verification tab
    Then the consumer should see only active members in the Household Members table
