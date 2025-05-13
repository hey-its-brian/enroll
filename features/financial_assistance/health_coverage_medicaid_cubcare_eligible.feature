Feature: medicaid_cubcare_eligible-related fields properly handle user input in Financial Assistance Application

  Background: User logs in and visits applicant's health coverage page
    Given bs4_consumer_flow feature is enabled
    Given a consumer, with a family, exists
    And is logged in
    And the consumer is RIDP verified
    And the FAA feature configuration is enabled
    And the user will navigate to the FAA Household Info page
    And FAA display_medicaid_question feature is enabled
    And has_medicare_cubcare_eligible feature is enabled
    When they click ADD INCOME & COVERAGE INFO for an applicant
    Then they should be taken to the applicant's Tax Info page
    And they visit the Health Coverage page via the left nav (also confirm they are on the Health Coverage page)

  Scenario: User can enter dates in the medicaid_cubcare_due_on field
    Given the user answers yes to having MaineCare coverage end date
    When the user sets "medicaid_cubcare_due_on" date field to "2025-05-15"
    Then the date in field "medicaid_cubcare_due_on" should be "2025-05-15"
    And the user clicks continue, the applicant "medicaid_cubcare_due_on" has updated value "2025-05-15"

  Scenario: User can enter dates in the person_coverage_end_on field
    Given the user answers yes to eligibility changed question
    When the user sets "person_coverage_end_on" date field to "2025-05-15"
    Then the date in field "person_coverage_end_on" should be "2025-05-15"
    And the user clicks continue, the applicant "person_coverage_end_on" has updated value "2025-05-15"
