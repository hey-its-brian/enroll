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
		And user clicks comfirm member
		Then the user will have to accept alert pop up for missing field