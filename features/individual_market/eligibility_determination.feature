Feature: User views Eligibility Determination after submission and on the Eligibility Determination Details page

  Background: User has existing qhp application
    Given bs4_consumer_flow feature is enabled
    And the FAA feature configuration is enabled
    And the date is within open enrollment
    And qhp_application feature is enabled
    And AI AN Details feature is enabled
    And the qhp consumer has an existing determined application
    And the qhp consumer is RIDP verified
    And the qhp consumer is logged in
    And the qhp consumer navigates to 'update application'

  Scenario: a household with all eligible applicants should show in the results page
    When the qhp consumer clicks continue to next step to the 'preferences' page
    Then the user should see the contact preferences page
    When the qhp consumer clicks continue to next step to the 'review' page
    Then the user should see the review application page
    When the qhp consumer clicks continue to next step to the 'submit' page
    Then the user should see the submit application page
    And the qhp consumer agrees and submits QHP application
    Then the qhp consumer should see the eligibility determination page
    And the qhp consumer should see that both have uqhp eligibility
    And the qhp consumer should see both applicants are not csr eligible
    When the user visits the current applications page
    And clicks the "View Eligibility Determination" for applicable application link
    Then the qhp consumer should see the eligibility determination details page
    And the qhp consumer should see that both have uqhp eligibility
    And the qhp consumer should see both applicants are not csr eligible

  Scenario Outline: the ai_an status of an applicant should affect eligibility determination
    Given the ai_an_self_attestation feature is enabled
    When the primary applicant has AI_AN marked as <primary_is_ai_an>
    When the dependent applicant has AI_AN marked as <dependent_is_ai_an>
    And the qhp consumer completes and submits the qhp application
    Then the qhp consumer should see that both have uqhp eligibility
    And the qhp consumer should see that <role> have csr eligibility
    When the user visits the current applications page
    And clicks the "View Eligibility Determination" for applicable application link
    Then the qhp consumer should see that both have uqhp eligibility
    And the qhp consumer should see that <role> have csr eligibility

  Examples:
    | primary_is_ai_an      | dependent_is_ai_an      | role       |
    | true                  | false                   | primary    |
    | false                 | true                    | dependent  |
    | true                  | true                    | both       |

  Scenario Outline: the incarceration status of an applicant should affect eligibility determination
    When the primary applicant has is_incarcerated marked as <primary_is_incarcerated>
    When the dependent applicant has is_incarcerated marked as <dependent_is_incarcerated>
    And the qhp consumer completes and submits the qhp application
    Then the qhp consumer should see that <eligible_roles> have uqhp eligibility
    And the qhp consumer should see that <ineligible_roles> are totally ineligible
    When the user visits the current applications page
    And clicks the "View Eligibility Determination" for applicable application link
    Then the qhp consumer should see that <eligible_roles> have uqhp eligibility
    And the qhp consumer should see that <ineligible_roles> are totally ineligible

  Examples:
    | primary_is_incarcerated    | dependent_is_incarcerated    | eligible_roles    | ineligible_roles    |
    | true                       | false                        | dependent         | primary             |
    | false                      | true                         | primary           | dependent           |
    | true                       | true                         | none              | both                |

  Scenario Outline: the address of an applicant should affect eligibility determination
    When the primary applicant has eligible_address marked as <primary_eligible_address_status>
    When the dependent applicant has eligible_address marked as <dependent_eligible_address_status>
    And the qhp consumer completes and submits the qhp application
    Then the qhp consumer should see that <eligible_roles> have uqhp eligibility
    And the qhp consumer should see that <ineligible_roles> are totally ineligible
    When the user visits the current applications page
    And clicks the "View Eligibility Determination" for applicable application link
    Then the qhp consumer should see that <eligible_roles> have uqhp eligibility
    And the qhp consumer should see that <ineligible_roles> are totally ineligible

  Examples:
    | primary_eligible_address_status | dependent_eligible_address_status | eligible_roles    | ineligible_roles    |
    | false                           | true                              | dependent         | primary             |
    | true                            | false                             | primary           | dependent           |
    | false                           | false                             | none              | both                |

  Scenario Outline: the lawful presence of an applicant should affect eligibility determination
    When the primary applicant has us_citizen marked as <primary_is_us_citizen>
    When the dependent applicant has us_citizen marked as <dependent_is_us_citizen>
    And the qhp consumer completes and submits the qhp application
    Then the qhp consumer should see that <eligible_roles> have uqhp eligibility
    And the qhp consumer should see that <ineligible_roles> are totally ineligible
    When the user visits the current applications page
    And clicks the "View Eligibility Determination" for applicable application link
    Then the qhp consumer should see that <eligible_roles> have uqhp eligibility
    And the qhp consumer should see that <ineligible_roles> are totally ineligible

  Examples:
    | primary_is_us_citizen  | dependent_is_us_citizen  | eligible_roles    | ineligible_roles    |
    | false                  | true                     | dependent         | primary             |
    | true                   | false                    | primary           | dependent           |
    | false                  | false                    | none              | both                |

  Scenario Outline: applicants not applying for coverage should not be included in the eligibility determination
    When the primary applicant has applying_coverage marked as <primary_applying_coverage>
    When the dependent applicant has applying_coverage marked as <dependent_applying_coverage>
    And the qhp consumer completes and submits the qhp application
    Then the qhp consumer should see that <eligible_roles> have uqhp eligibility
    And the qhp consumer should see that <ineligible_roles> did not apply for coverage
    When the user visits the current applications page
    And clicks the "View Eligibility Determination" for applicable application link
    Then the qhp consumer should see that <eligible_roles> have uqhp eligibility
    And the qhp consumer should see that <ineligible_roles> did not apply for coverage

  Examples:
    | primary_applying_coverage  | dependent_applying_coverage  | eligible_roles    | ineligible_roles    |
    | false                      | true                         | dependent         | primary             |
    | true                       | false                        | primary           | dependent           |
    | false                      | false                        | none              | both                |


