Feature: A dedicated page that gives the user access to Tax Info page for a given applicant as well as Financial application forms for each household member.

  Background: User can edit tax info page for a household member
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
    Given ssi types feature is enabled
    And they click ADD INCOME & COVERAGE INFO for an applicant

  Scenario Outline: User lands on Tax Info page
    Given FAA spousal_tax_info_validation feature is <is_enabled>
    And they click ADD INCOME & COVERAGE INFO for an applicant
    Then the user should see the Tax Info title
    Then the user can <can_see_spousal_filing_informational_banner> the spousal filing informational banner
    # TODO - add other assertions on default page content like navigation pane, navigation buttons, radios, etc

    Examples:
      | is_enabled | can_see_spousal_filing_informational_banner |
      | enabled    | see                                         |
      | disabled   | not see                                     |

  Scenario Outline: User submits Tax Info form with applicant errors
    And they click ADD INCOME & COVERAGE INFO for an applicant
    And the applicant has a <error_domain> applicant error
    And the enter in required tax info fields
    When the user clicks on the CONTINUE button
    Then they should see the <error_message> error banner

    Examples:
      | error_domain | error_message                                                                                                                  |
      | job income   | Job income is missing required information. Please complete all required fields to proceed with submitting your application.   |
      | other income | Other income is missing required information. Please complete all required fields to proceed with submitting your application. |

