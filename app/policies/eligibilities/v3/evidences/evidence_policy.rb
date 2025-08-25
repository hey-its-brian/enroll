# frozen_string_literal: true

module Eligibilities
  module V3
    module Evidences
      # This class defines the policy for Evidence in the Eligibilities module.
      class EvidencePolicy < ::ApplicationPolicy

        # Initializes the EvidencePolicy with a user and a record.
        # It sets the @family instance variable to the family of the evidence record.
        #
        # @param user [User] the user who is performing the action
        # @param record [Evidence] the evidence that the user is trying to access or modify
        def initialize(user, record)
          super
          @family ||= record.eligibility.eligible.application.family
        end

        # Determines if the current user has permission to view all documents for an applicant.
        # The user can view all documents for the applicant if they have permission to edit it.
        #
        # @return [Boolean] Returns true if the user has permission to upload a document for an applicant, false otherwise.
        def index?
          edit?
        end

        # Determines if the current user has permission to upload a document for an applicant.
        # The user can upload a document for the applicant if they have permission to edit it.
        #
        # @return [Boolean] Returns true if the user has permission to upload a document for an applicant, false otherwise.
        def upload?
          edit?
        end

        # Determines if the current user has permission to download a document from an applicant.
        # The user can download a document from the applicant if they have permission to edit it.
        #
        # @return [Boolean] Returns true if the user has permission to download a document from an applicant, false otherwise.
        def download?
          edit?
        end

        # Determines if the current user has permission to destroy an applicant.
        # The user can destroy an applicant if they have permission to edit it.
        #
        # @return [Boolean] Returns true if the user has permission to destroy an applicant, false otherwise.
        def destroy?
          edit?
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
      end
    end
  end
end
