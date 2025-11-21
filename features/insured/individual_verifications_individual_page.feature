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

  Scenario: Consumer sees the disclaimer
    And EnrollRegistry verifications_household_summary_text_update feature is enabled
    And the consumer selects a household member
    Then the consumer should see Individual disclaimer

  Scenario: Consumer has inactive and active verifications
    And EnrollRegistry show_identity_verification feature is enabled
    And EnrollRegistry show_inactive_verifications feature is enabled
    And that the consumer has inactive verifications
    And Hbx Admin exists
    When the consumer selects a household member
    Then the user should see the Individual verifications table
    And the user should not see the Individual inactive verifications table
    And consumer logs out
    And that a user with a HBX staff role with HBX staff subrole exists and is logged in
    And the admin visits the verification tab
    And the admin selects a household member
    Then the admin should see the Individual verifications table
    And the admin should see the Individual inactive verifications table

  Scenario: Consumer has inactive FFA verifications
    Given show_previous_year_faa_verifications feature is enabled
    Given qhp_application feature is enabled
    And EnrollRegistry show_identity_verification feature is enabled
    And EnrollRegistry show_inactive_verifications feature is enabled
    Given the consumer has a previous year FA application that needs verifications
    Given the consumer has a determined QHP application
    And Hbx Admin exists
    When the consumer selects a household member
    Then the user should see the Individual verifications table
    And the user should not see the Individual inactive verifications table
    And consumer logs out
    And that a user with a HBX staff role with HBX staff subrole exists and is logged in
    And the admin visits the verification tab
    And the admin selects a household member
    Then the admin should see the Individual verifications table
    And the admin should see the Individual inactive verifications table
    Then there should be FA related inactive verifications listed

  Scenario: Consumer goes to the Verification Detail page from the Individual table
    And the consumer selects a household member
    When the consumer selects the verification for the member
    Then the consumer should see the verification detail page

  Scenario: Consumer presses the Back to Verifications button
    And the consumer selects a household member
    When the consumer presses the Back to Verifications button
    Then the consumer should see the verifications household summary page
