Feature: Hbx Admin Bulk Notice

Background: Admin has ability to create a new Bulk Notice
  Given bs4_consumer_flow feature is enabled
  Given bs4_admin_flow feature is enabled
  Given assister_agency feature is enabled
  Given an HBX admin exists
  And the HBX admin is logged in
  And there is an employer ACME
  And there is a Broker Agency exists for ACME
  And there is a Assister Agency exists for ACME

Scenario: Admin will create a new bulk notice for Assister Agency
  Given Admin is on the new Bulk Notice view
  When Admin selects Assister Agency
  And Admin fills form with AssisterAgency FEIN
  Then Admin should see AssisterAgency badge
  When Admin fills in the rest of the form
  And Admin clicks on Preview button
  Then Admin should see the Preview Screen

Scenario: Admin will create a new bulk notice for Broker Agency
  Given Admin is on the new Bulk Notice view
  When Admin selects Broker Agency
  And Admin fills form with BrokerAgency FEIN
  Then Admin should see BrokerAgency badge
  When Admin fills in the rest of the form
  And Admin clicks on Preview button
  Then Admin should see the Preview Screen
