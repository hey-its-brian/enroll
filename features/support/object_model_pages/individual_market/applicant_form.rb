# frozen_string_literal: true

# Applicant form
module IndividualMarket
  # Form data for qhp applicants
  class ApplicantForm
    def self.applicant_first_name
      'applicant[person_name_attributes][given_name]'
    end

    def self.applicant_last_name
      'applicant[person_name_attributes][family_name]'
    end

    def self.applicant_form_dob
      'applicant[demographics_attributes][dob]'
    end

    def self.applicant_form_ssn
      'applicant[demographics_attributes][ssn]'
    end

    def self.applicant_form_no_ssn
      'applicant[demographics_attributes][no_ssn]'
    end

    def self.applicant_relationship
      'applicant[relationship]'
    end

    def self.applicant_gender_select
      'applicant[demographics_attributes][gender]'
    end

    def self.is_applying_coverage_true
      'applicant_is_applying_coverage_true'
    end

    def self.is_applying_coverage_false
      'applicant_is_applying_coverage_false'
    end

    def self.radio_incarcerated
      'applicant[demographics_attributes][is_incarcerated]'
    end

    def self.radio_incarcerated_no
      'applicant[demographics_attributes][is_incarcerated]'
    end

    def self.indian_tribe_member
      'applicant[demographics_attributes][indian_tribe_member]'
    end

    def self.indian_tribe_no
      'applicant[demographics_attributes][indian_tribe_member]'
    end

    def self.indian_tribe_yes
      'applicant[demographics_attributes][indian_tribe_member]'
    end

    def self.indian_tribe_state
      'applicant[demographics_attributes][tribal_state]'
    end

    def self.indian_tribe_other_code
      'applicant_demographics_attributes_tribe_codes_ot'
    end

    def self.indian_tribe_other_name
      'applicant[demographics_attributes][tribal_name]'
    end

    def self.address_state
      'applicant[addresses_attributes][0][state]'
    end

    def self.address_zip
      'applicant[addresses_attributes][0][zip]'
    end

    def self.address_same_as_primary
      'applicant[address_same_as_primary]'
    end

    def self.address_line1
      'applicant[addresses_attributes][0][address_1]'
    end

    def self.address_city
      'applicant[addresses_attributes][0][city]'
    end

    def self.us_citizen
      'applicant[demographics_attributes][us_citizen]'
    end

    def self.eligible_immigration_status
      'applicant[demographics_attributes][eligible_immigration_status]'
    end

    def self.naturalized_citizen
      'applicant[demographics_attributes][naturalized_citizen]'
    end

    def self.confirm_member_button
      '[data-cuke="confirm-member"]'
    end

    def self.save_changes_button
      '[data-cuke="save-changes"]'
    end

    def self.edit_primary_applicant
      '[data-cuke="edit-primary-applicant"]'
    end

    def self.edit_dependent_button
      '[data-cuke="edit-dependent-applicant"]'
    end

    def self.remove_dependent_button
      '[data-cuke="remove-dependent-applicant"]'
    end

    def self.confirm_remove_dependent_button
      '[data-cuke="confirm-remove-dependent-applicant"]'
    end
  end
end
