Feature: A dedicated page that gives the user access to household member creation/edit as well as Financial application forms for each household member.

  Background:
    Given the FAA feature configuration is enabled
    When the user is applying for a CONSUMER role
    And the primary member has filled mandatory information required
    And the primary member authorizes system to call EXPERIAN
    And system receives a positive response from the EXPERIAN
    And the user answers all the VERIFY IDENTITY  questions
    And the person named Patrick Doe is RIDP verified
    When the user clicks on submit button
    And the Experian returns a VERIFIED response
    Then the user will navigate to the Help Paying for Coverage page
    And saves a YES answer to the question: Do you want to apply for Medicaid…

  Scenario: new applicant navigation to the FAA Household Info page
    Given that the user is on the Application Checklist page
    When the user clicks CONTINUE
    Then the user will navigate to the FAA Household Infor: Family Members page

  Scenario: Eligible Immigration Status checkbox appears when feature is enabled
    Given eligible immigration status checkbox feature is enabled
    Given that the user is on the Application Checklist page
    When the user clicks CONTINUE
    And consumer clicks on pencil symbol next to primary person
    And consumer chooses no for us citizen
    Then consumer should see the eligible immigration status checkbox

  Scenario: Individual cannot edit dependent dob and ssn
    Given bs4_consumer_flow feature is enabled
    And EnrollRegistry people_tab feature is enabled
    And that the user is on the Application Checklist page
    When user clicks Begin Application
    And the user has a dependent
    And consumer edits the dependent of the application
    Then the user should see disabled dob field for the applicant

  Scenario: Individual can edit dependent SSN if no SSN exists
    Given bs4_consumer_flow feature is enabled
    And EnrollRegistry people_tab feature is enabled
    And that the user is on the Application Checklist page
    When user clicks Begin Application
    And the user has a dependent with no ssn
    And consumer edits the dependent of the application
    Then the user should see ssn editable & dob field disabled for the applicant

  Scenario: Confirm Member button re-enables when modal is closed with X button
    Given bs4_consumer_flow feature is enabled
    And EnrollRegistry people_tab feature is enabled
    And that the user is on the Application Checklist page
    When user clicks Begin Application
    And the user has a dependent with no ssn and modal handling
    When user clicks confirm member and handles modal
    Then the confirm member button should be re-enabled

  Scenario: Confirm Member button remains disabled when modal OK button is clicked
    Given bs4_consumer_flow feature is enabled
    And EnrollRegistry people_tab feature is enabled
    And that the user is on the Application Checklist page
    When user clicks Begin Application
    And the user has a dependent with no ssn and modal handling
    When user clicks confirm member and accepts modal
    Then the confirm member button should remain disabled

  Scenario: Individual can edit dependent SSN via alphanumeric inputs
    Given bs4_consumer_flow feature is enabled
    And EnrollRegistry people_tab feature is enabled
    And that the user is on the Application Checklist page
    When user clicks Begin Application
    And the user has a dependent with no ssn
    And consumer edits the dependent of the application
    Then the user should see ssn editable & dob field disabled for the applicant
    When the user enters their own ssn for the dependent
    When the user enters "8719" in the dependent ssn field
    Then the ssn input field should format as "871-9"