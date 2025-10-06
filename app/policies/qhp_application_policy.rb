# frozen_string_literal: true

# The QhpApplicationPolicy class defines the policy for accessing individual market applications.
# It provides methods to check if a user has the necessary permissions to perform various actions on an application.
class QhpApplicationPolicy < ApplicationPolicy

  def initialize(user, record)
    super
    @family ||= record.family
  end

  # States if a family is present on the application.
  # This is used to determine if the application is a true application or a placeholder for a new/missing application.
  # @return [Boolean] Returns true if the application has a family, false otherwise.
  def find_application?
    @family.present?
  end

  # Determines if the current user has permission to copy the application.
  # The user can copy the application if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to copy the application, false otherwise.
  def copy?
    edit?
  end

  # Determines if the current user has permission to edit.
  # The user can edit if they are a primary family member,
  # an active associated broker or assister staff, an active associated broker, or an admin in the individual market.
  #
  # @return [Boolean] Returns true if the user has permission to edit, false otherwise.
  def edit?
    return true if individual_market_primary_family_member?
    return true if active_associated_individual_market_family_broker_staff?
    return true if active_associated_individual_market_family_assister_staff?
    return true if active_associated_individual_market_family_broker?
    return true if active_associated_individual_market_family_assister?
    return true if individual_market_admin?

    false
  end

  # Determines if the current user has permission to review the application.
  # The user can review the application if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to review the application, false otherwise.
  def review?
    edit?
  end

  # Determines if the current user has permission to view the preferences the application.
  # The user can see the preferences if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to see the preferences page of the application, false otherwise.
  def preferences?
    edit?
  end

  # Determines if the current user has permission to edit the attestation the application.
  # The user can update the attestation if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to edit the attestation page of the application, false otherwise.
  def attestation?
    edit?
  end

  # Determines if the current user has permission to submit the application.
  # The user can submit the application if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to submit the application, false otherwise.
  def submit?
    edit?
  end

  # Determines if the current user has permission to view the eligibility results of the application.
  # The user can see the eligibility results if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to see the eligibility results page of the application, false otherwise.
  def eligibility_results?
    edit?
  end

  # Determines if the current user has permission to view the application.
  # The user can see the full application details if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to see the application details page of the application, false otherwise.
  def application_details?
    edit?
  end

  # Determines if the current user has permission to create a new applicant.
  # The user can create a new applicant if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to create a new applicant, false otherwise.
  def new_applicant?
    edit?
  end

  # Determines if the current user has permission to show the ssn of the applicant.
  # The user can show the ssn if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to show the ssn of the applicant, false otherwise.
  def can_show_ssn?
    edit?
  end

  # Determines if the current user has permission to view the index of applicant.
  # The user can view the index of the applicant if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to view the index of the application's applicant, false otherwise.
  def applicants?
    edit?
  end

  # Determines if the current user has permission to view the eligibility criteria of the application.
  # The user can view the eligibility criteria if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to view the eligibility criteria of the application, false otherwise.
  def eligibility_criteria?
    return true if individual_market_admin?

    false
  end

  # Determines if the current user has permission to view the submit and determine error of the application.
  # The user can view the submit and determine error if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to view the submit and determine error of the application, false otherwise.
  def submit_and_determine_error?
    edit?
  end

  # Determines if the current user has permission to view the application year selection of the application.
  # The user can view the application year selection if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to view the application year selection of the application, false otherwise.
  def application_year_selection?
    edit?
  end

  # Determines if the current user has permission to update the application year of the application.
  # The user can update the application year if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to update the application year of the application, false otherwise.
  def update_application_year?
    edit?
  end
end
