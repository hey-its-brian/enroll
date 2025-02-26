Feature: HBX Admin Edits a Assister Applicant

  Scenario: Primary Assister has not signed up on the HBX
    Given a CCA site exists with a benefit market
    Given all permissions are present
    And Health and Dental plans exist
    And there is a Assister Agency exists for District Assisters Inc
    And the assister Max Planck is primary assister for District Assisters Inc

    Given that a user with a HBX staff role with HBX staff subrole exists and is logged in
    # Skipped the steps here due to constant intermittent failures with clicking links
    And HBX Admin visits the Edit Assister Applicant page for Max Planck of agency District Assisters Inc
    And HBX Admin edits the assister application and clicks update
    Then the HBX Admin should see a success message that the assister application was successfully updated

