# frozen_string_literal: true

# The ApplicantPolicy class defines the policy for accessing and modifying applicants.
# It determines what actions a user can perform on an applicant based on their roles and permissions.
class ApplicantPolicy < ApplicationPolicy

  # Initializes the ApplicantPolicy with a user and a record.
  # It sets the @family instance variable to the family of the applicant record.
  #
  # @param user [User] the user who is performing the action
  # @param record [Applicant] the applicant that the user is trying to access or modify
  def initialize(user, record)
    super
    @family ||= record.application.family
  end

  # Determines if the current user has permission to edit the applicant.
  # The user can edit the applicant if they are a primary family member,
  # an admin, an active associated broker or assister staff, or an active associated broker in the individual market.
  #
  # @return [Boolean] Returns true if the user has permission to edit the applicant, false otherwise.
  def edit?
    return true if individual_market_primary_family_member?
    return true if active_associated_individual_market_family_broker_staff?
    return true if active_associated_individual_market_family_assister_staff?
    return true if active_associated_individual_market_family_broker?
    return true if active_associated_individual_market_family_assister?
    return true if individual_market_admin?

    false
  end

  # Determines if the current user has permission to create a new applicant.
  # The user can create a new applicant if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to create a new applicant, false otherwise.
  def new?
    edit?
  end

  # Determines if the current user has permission to destroy an applicant.
  # The user can destroy an applicant if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to destroy an applicant, false otherwise.
  def destroy?
    edit?
  end

  # Determines if the current user has permission to see an applicant.
  # The user can see an applicant if they have permission to edit it.
  #
  # @return [Boolean] Returns true if the user has permission to see an applicant, false otherwise.
  def show?
    edit?
  end
end
