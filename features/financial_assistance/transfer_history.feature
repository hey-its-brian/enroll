Feature: Cost Savings Transfer History

  Admin will be able to access Cost Savings - Transfer History action only when
  Financial Assistance feature is enabled. When FAA feature disabled,
  consumer shall not be able see or access Transfer History page.

  Background:
    Given bs4_consumer_flow feature is enabled
    Given bs4_admin_flow feature is enabled
    Given the FAA feature configuration is enabled
    Given FAA transfer_history_page feature is enabled
    And Individual Market with open enrollment period exists
    And FAA display_medicaid_question feature is enabled
    And a family with financial application and applicants in determined state exists
    And the primary applicant age greater than 18
    And the user is RIDP verified
    Given a Hbx admin with hbx_staff role exists
    When a Hbx admin logs on to Portal
    And Hbx Admin click Families link
    And Hbx Admin clicks on a family member

  Scenario: FAA Feature Is Enabled - Admin logs in and clicks on Person, QHP Enabled
    Given qhp_application feature is enabled
    And the admin selects 'Applications' from the sidebar
    When admin clicks on Action dropdown
    Then the admin should see text Transfer History
    Then admin clicks on Transfer History action
    And admin is on the Transfer History page
    And admin should see the back to application button
    And admin should see breadcrumbs
    And admin should see the transfer history table

  Scenario: No transfers for the application
    Given qhp_application feature is enabled
    And the admin selects 'Applications' from the sidebar
    When admin clicks on Action dropdown
    Then the admin should see text Transfer History
    Then admin clicks on Transfer History action
    And admin is on the Transfer History page
    And admin should see the 'no history available' message

  Scenario: Given the application has been transferred
    Given qhp_application feature is enabled
    Given the application has been transferred
    And the admin selects 'Applications' from the sidebar
    When admin clicks on Action dropdown
    Then the admin should see text Transfer History
    Then admin clicks on Transfer History action
    And admin is on the Transfer History page
    And admin should not see the 'no history available' message
    And admin should see the transfer in the table

  Scenario: FAA Feature Is Enabled - Admin logs in and clicks on Person, QHP Disabled
    And qhp_application feature is disabled
    And admin clicks on Cost Savings link
    When admin clicks on Action dropdown
    Then the admin should see text Transfer History
    Then admin clicks on Transfer History action
    And admin is on the Transfer History page
    And admin should see the back to applications button
    And admin should not see breadcrumbs
    And admin should see the transfer history table
