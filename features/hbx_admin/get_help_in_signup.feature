Feature: Get Help in Signing Up from Assister/Broker
  Background:
    Given bs4_consumer_flow feature is enabled
    Given bs4_broker_flow feature is enabled
    Given bs4_admin_flow feature is enabled
    Given assister_agency feature is enabled
    Given that a user with a HBX staff role with hbx_tier3 subrole exists
    And Hbx Admin logs on to the Hbx Portal
    And the Admin is on the Main Page
    And Patrick Doe has active individual market role and verified identity

  Scenario: Admin can view assisters and can select them
    When create an IVL Assister Agency exists
    When Admin clicks Families tab
    Then the Admin is navigated to the Families screen
    And I click the name of Patrick Doe from family list
    And clicks on #help_me_sign_up
    And clicks on #bottom_expert_assister_link
    Then assister record exists and should be able to click on the Select button
    And should be able to click on the Select This broker button
    Then should be able to see the success message

  Scenario: Admin can view brokers and can select them
    When create an IVL Broker Agency exists
    When Admin clicks Families tab
    Then the Admin is navigated to the Families screen
    And I click the name of Patrick Doe from family list
    And clicks on #help_me_sign_up
    And clicks on #bottom_expert_link
    Then broker record exists and should be able to click on the Select button
    And should be able to click on the Select This broker button
    Then should be able to see the success message




