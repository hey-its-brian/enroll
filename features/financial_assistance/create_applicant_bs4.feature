Feature: Create a new applicant with Bootstrap 4 layout enabled

  Background: User logs in and visits application home page
  	Given bs4_consumer_flow feature is enabled
    Given divorce agreement year feature is enabled
    Given FAA other_income_end_date_warning feature is enabled
    Given a consumer, with a family, exists
    And is logged in
    And a benchmark plan exists
    And the consumer is RIDP verified
    And the FAA feature configuration is enabled
    Given FAA income_and_deduction_date_warning feature is enabled
    When the user will navigate to the FAA Household Info page

	Scenario: User adds a new applicant with non-citizen status
		Given Individual clicks on Add New Person
		Then the user enters applicant information with us citizen false
		And the user clicks the confirm member button
		Then the user will have to accept alert pop up for missing field

  Scenario: User edits an existing applicant with Immigration status
    Given a consumer with immigration status exists
    And the user edits the primary applicant
    Then fields related to the applicant vlp document should display

  Scenario: User edits an existing applicant with tribal status
    Given a consumer with tribe status exists
    And the user edits the primary applicant
    Then fields related to the consumer tribal status should display

  Scenario Outline: User adds a new applicant with eligibile immigration status and selects <vlp_document_option>
    Given Individual clicks on Add New Person
    And Individual selects no for applicant's us_citizen status
    And Individual selects yes for applicant's eligibile immigration status
    When Individual selects <vlp_document_option> immigration document option
    Then Individual <should_see> see the pre-1957 alien number warning

    Examples:
      | vlp_document_option                                                        | should_see |
      | Certificate of citizenship                                                 | should     |
      | Naturalization certificate                                                 | should     |
      | I-327 – Reentry permit                                                     | should not |
      | I-551 – Permanent resident card                                            | should not |
      | I-571 – Refugee travel document                                            | should not |
      | I-766 – Employment authorization card                                      | should not |
      | Machine-readable immigrant visa (with temporary I-551 language)            | should not |
      | Temporary I-551 stamp (on passport or I-94)                                | should not |
      | I-94 – Arrival/departure record                                            | should not |
      | I-94 – Arrival/departure record in unexpired foreign passport              | should not |
      | Unexpired foreign passport                                                 | should not |
      | I-20 – Certificate of eligibility for nonimmigrant student (F-1) status    | should not |
      | DS-2019 Certificate of eligibility for exchange visitor (J-1) status       | should not |
      | Other (with alien number)                                                  | should not |
      | Other (with I-94 number)                                                   | should not |

  Scenario Outline: User adds a new naturalized applicant and selects <vlp_document_option>
    Given Individual clicks on Add New Person
    And Individual selects yes for applicant's us_citizen status
    And Individual selects yes for applicant's naturalized_citizen status
    When Individual selects <vlp_document_option> naturalization document option
    Then Individual <should_see> see the pre-1957 alien number warning

    Examples:
      | vlp_document_option                                                        | should_see |
      | Certificate of Citizenship                                                 | should     |
      | Naturalization Certificate                                                 | should     |

 Scenario: User selects Other race or ethnicity option
		Given Individual clicks on Add New Person
		And the user selects Other option for race
    Then the user should see the Other options autopopulate for ethnicity
