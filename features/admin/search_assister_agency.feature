Feature: Add searchbox on assister agencies
  In order for the Hbx admin to search for assister agencies through searchbox

  Scenario: Search for a assister agency
    Given bs4_broker_flow feature is enabled
    And bs4_admin_flow feature is enabled
    And assister_agency feature is enabled
    And bs4_consumer_flow feature is disable
    Given there is a Assister Agency exists for District Assisters Inc
    And the assister Max Planck is primary assister for District Assisters Inc
    Given Hbx Admin exists
    When Hbx Admin logs on to the Hbx Portal
    Then Hbx Admin is on Assister Index of the Admin Dashboard
    When Hbx Admin is on Assister Index and clicks Assister Agencies
    Then Hbx Admin should see search box
    When Assister he enters an assister agency name and clicks on the search button
    Then Assister he should see the one result with the agency name
