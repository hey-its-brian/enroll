Feature: The edit page for an Financial Assistance application which displays a high level Applicant interface

  Background: User exists
    Given bs4_consumer_flow feature is enabled
    Given divorce agreement year feature is enabled
    Given FAA other_income_end_date_warning feature is enabled
    Given a consumer, with a family, exists
    And is logged in
    And a benchmark plan exists
    And the consumer is RIDP verified
    And the FAA feature configuration is enabled
    Given FAA income_and_deduction_date_warning feature is enabled

  Scenario: User lands on Family Info page
    When the user visits the Family Info page for the consumer's Financial Assistance application
    Then the user should see the Family Info title
    # TODO - add other assertions on default page content like navigation pane, navigation buttons, applicant rows, etc.

  Scenario: Application is lacking Applicant information
    And the consumer's application has all incomplete applicants
    When the user visits the Family Info page for the consumer's Financial Assistance application
    Then the continue button should be disabled

  Scenario Outline: Application has complete Applicant information but invalid spousal tax info
    And FAA spousal_tax_info_validation feature is enabled
    And the consumer's application has all complete applicants
    And the consumer's application has <valid_spousal_tax_information> spousal tax information 
    When the user visits the Family Info page for the consumer's Financial Assistance application
    Then the user can <can_see_spousal_filing_warning_banner> the spousal filing warning banner
    And the continue button should be <continue_enabled>

    Examples:
    | valid_spousal_tax_information | can_see_spousal_filing_warning_banner | continue_enabled |
    | valid                         | not see                               | enabled          |
    | invalid                       | see                                   | disabled         |
