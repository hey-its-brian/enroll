Feature: Individual Verification Details Page
  Background:
    Given bs4_consumer_flow feature is enabled
    And show_new_verifications_household_summary feature is enabled

  Scenario Outline: Consumer visits the verification details Page for a status
    And a consumer exists
    And the consumer is logged in
    And consumer has successful ridp
    When the consumer visits the verification detail page for a verification with <status> status
    Then the consumer should the summary header with the <user_facing_status> status
    And the consumer should see the summary header <with_or_without_reason> the status reason
    And the consumer should <see_or_not_see_actionable_status> a actionable status
    And the consumer should <see_or_not_see_upload_section> the upload section

    Examples:
      | status                     | user_facing_status | with_or_without_reason | see_or_not_see_actionable_status | see_or_not_see_upload_section |
      | rejected                   | rejected           | with                   | see                              | see                           |
      | outstanding                | outstanding        | without                | see                              | see                           |
      | review                     | review             | without                | not see                          | see                           |
      | pending                    | pending            | without                | not see                          | not_see                       |
      | verified                   | verified           | without                | not see                          | not see                       |
      | attested                   | attested           | without                | not see                          | not see                       |
      | negative_response_received | not applicable     | without                | not see                          | see                           |
      | curam                      | verified           | without                | not see                          | not see                       |

  Scenario: Consumer presses the Back to Individual button
    And a consumer exists
    And the consumer is logged in
    And consumer has successful ridp
    When the consumer visits the verification detail page
    And the consumer presses the Back to Individual button
    Then the consumer should see the individual detail page

  Scenario Outline: Consumer sees the documents we accept section
    And EnrollRegistry show_new_documents_types feature is enabled
    And a consumer exists
    And the consumer is logged in
    And consumer has successful ridp
    When the consumer visits the verification detail page for a <type> verification with review status
    And the consumer expands all accordions
    Then the consumer should see the <type> documents we accept section

    Examples:
    | type                          |
    | Citizenship                   |
    | Social Security Number        |
    | Income                        |
    | Coverage from a job           |
    | Coverage from another program |

  Scenario Outline: Admin actions available based on verification type and status
    And EnrollRegistry verification_due_on_options feature is enabled
    And EnrollRegistry ai_an_self_attestation feature is enabled
    And a consumer exists
    And Hbx Admin exists
    And that a user with a HBX staff role with HBX staff subrole exists and is logged in
    When the admin visits the verification detail page for a <type> verification with <status> status
    Then the admin actions dropdown should have options: <expected_options>
    And the "View verification history" link should be visible

    Examples:
      | type                   | status      | expected_options                       |
      | Citizenship            | verified    | Verify, Reject, Call HUB               |
      | Citizenship            | outstanding | Verify, Call HUB, Extend               |
      | Citizenship            | rejected    | Verify, Reject, Call HUB, Extend       |
      | Immigration status     | verified    | Verify, Reject, Call HUB               |
      | Immigration status     | outstanding | Verify, Call HUB, Extend               |
      | Immigration status     | rejected    | Verify, Reject, Call HUB, Extend       |
      | Social Security Number | verified    | Verify, Reject, Call HUB               |
      | Social Security Number | outstanding | Verify, Call HUB, Extend               |
      | Social Security Number | rejected    | Verify, Reject, Call HUB, Extend       |
      | Alive Status           | verified    | Verify, Reject                         |
      | Alive Status           | outstanding | Verify, Extend                         |
      | Alive Status           | rejected    | Verify, Reject, Extend                 |
      | American Indian Status | verified    | (no options)                           |
      | American Indian Status | outstanding | (no options)                           |
      | American Indian Status | rejected    | (no options)                           |

  Scenario Outline: Admin sees the extend verification due date option
    And a consumer exists
    And EnrollRegistry verification_due_on_options feature is enabled
    And all permissions are present
    And that a user with a HBX staff role with <subrole> subrole exists and is logged in
    And the admin visits the verification detail page for a verification with outstanding status
    Then the user should <should_see> see the set due date option

  Examples:
    | subrole            | should_see |
    | hbx_staff          | see        |
    | hbx_read_only      | not see    |
    | super_admin        | see        |
    | hbx_csr_tier1      | not see    |
    | hbx_csr_tier2      | not see    |
    | hbx_tier3          | not see    |

  Scenario Outline: Admin sees the admin verify/reject reasons
    And EnrollRegistry verifications_household_summary_text_update feature is enabled
    And a consumer exists
    And Hbx Admin exists
    And that a user with a HBX staff role with HBX staff subrole exists and is logged in
    And the admin visits the verification detail page for a verification with rejected status
    And the user selects the <type> option from the actions dropdown
    Then the user should see <reasons> in the reasons dropdown

  Examples:
    | type   | reasons                                                                                                 |
    | Verify | Document in EnrollApp, Document in DIMS, SAVE system, E-Verified in Curam, Salesforce, Self-Attestation |
    | Reject | Illegible, Incomplete Doc, Wrong Type, Wrong Person                                                     |


  Scenario Outline: Admin extends the verification due date
    And EnrollRegistry verification_due_on_options feature is enabled
    And a consumer exists
    And Hbx Admin exists
    And that a user with a HBX staff role with HBX staff subrole exists and is logged in
    And the admin visits the verification detail page for a verification with outstanding status
    And the user selects the Extend option from the actions dropdown
    And the user selects the <date_option> option from the extend due date dropdown
    When Admin clicks confirm
    Then the user should see the new date
    When Admin clicks on Verification History
    Then the user will see the date, action, and update reason for the extension action

  Examples:
    | date_option  |
    | 95 Day       |
    | 35 Day       |
    | Manual       |
