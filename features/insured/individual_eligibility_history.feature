Feature: Eligibility History Page

  Background:
    Given Individual has not signed up as an HBX user
    Given the FAA feature configuration is enabled
    Given bs4_consumer_flow feature is enabled
    Given qhp_application feature is enabled

    Scenario: Consumer visits the eligibility history page
    Given a consumer exists
    Given the consumer is logged in
    And consumer has successful ridp
    And consumer visits home page
    When consumer clicks on Applications link
    And consumer clicks on View Application History
    Then consumer should see the Eligibility History page
