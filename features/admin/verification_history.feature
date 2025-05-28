Feature: Admin navigates to the verification history page of a consumer

  Background: Setup site, consumer and Admin navigates to consumer account
    Given bs4_consumer_flow feature is enabled
    Given show_new_verifications_household_summary feature is enabled
    And the alive_status feature is enabled
    And a consumer exists
    And the consumer is completely verified
    And the determination for the family has been built
    And an HBX admin exists
    And clicks on the person in families tab
    And admin lands in the Verifications page

  Scenario: Admin can access to the Verification History page of an outstanding verification
    Given the consumer visits the verification detail page for a verification with outstanding status
    When admin clicks on Verification History
    Then the Verification History table is present

  Scenario: Admin can access to the Verification History page of a rejected verification
    Given the consumer visits the verification detail page for a verification with rejected status
    When admin clicks on Verification History
    Then the Verification History table is present

  Scenario: Admin can see history elements in correct order
    Given the consumer has a verification with history elements that have varying dates
    And the admin visits the verification tab
    And the admin selects a household member
    And the consumer selects the Income verification for the member
    And admin clicks on Verification History
    And the Verification History table is present
    Then the Verification History table should be sorted by date in reverse order

  Scenario: Admin can access to the Verification History page and return to the Document Detail
    Given the consumer visits the verification detail page for a verification with rejected status
    And admin clicks on Verification History
    And the Verification History table is present
    And admin clicks on the back button of the Verification History page
    Then admin should be in the Document Detail page
    When admin clicks on Verification History
    And admin clicks on the Document Detail breadcrumb
    Then admin should be in the Document Detail page
