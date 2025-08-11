# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Families
    module IndividualMarketEligibilities
      # Initiates the renewal process for individual market eligibilities for all families
      class InitiateRenewal
        include Dry::Monads[:do, :result]
        include EventSource::Command
        include ResourceRegistryHelper

        FA_APP_STATES = %w[applicants_update_required income_verification_extension_required].freeze

        # Initiates the renewal process for individual market eligibilities for all families
        #
        # @param renewal_year [Integer] the year for which the renewal is initiated
        #
        # @return [Dry::Monads::Result] Success with family IDs or Failure with an error message
        def call(renewal_year:)
          renewal_year      = yield validate(renewal_year)
          family_ids        = yield fetch_families_with_active_enrollments
          published_result  = yield publish_renewal_events(family_ids, renewal_year)

          Success(published_result)
        end

        private

        # Validates the renewal year
        #
        # @param renewal_year [Integer] the year to validate
        #
        # @return [Dry::Monads::Result] Success with the renewal year or Failure with an error message
        def validate(renewal_year)
          return Failure("QHP application feature is not enabled") unless qhp_application_feature_enabled?

          if renewal_year.is_a?(Integer) && renewal_year >= 2026
            Success(renewal_year)
          else
            Failure("Invalid renewal year: #{renewal_year}. Please provide a year greater than or equal to 2026.")
          end
        end

        # Fetches all families with active individual market enrollments for the current year
        #
        # @return [Dry::Monads::Result] Success with family IDs or Failure with an error message
        def fetch_families_with_active_enrollments
          Success(
            ::HbxEnrollment.only(
              :aasm_state, :effective_on, :family_id, :kind
            ).individual_market.enrolled.current_year.distinct(:family_id)
          )
        end

        # Publishes renewal events for each family eligible for individual market eligibility renewal
        #
        # @param family_ids [Array<String>] the IDs of families to process
        # @param renewal_year [Integer] the year for which the renewal is initiated
        #
        # @return [Dry::Monads::Result] Success with family IDs or Failure with an error message
        def publish_renewal_events(family_ids, renewal_year)
          Success(
            ::Family.only(:id, :latest_application_gid).where(:id.in => family_ids).inject([]) do |eligible_family_ids, family|
              if eligible_for_ivl_eligibility_renewal(family, renewal_year)
                generate_event_and_publish(family.id, renewal_year)
                eligible_family_ids << family.id
              end

              eligible_family_ids
            end
          )
        end

        # Checks if the family is eligible for individual market eligibility renewal
        #
        # @param family [Family] the family to check
        # @param renewal_year [Integer] the year for which the renewal is initiated
        #
        # @return [Boolean] true if eligible, false otherwise
        def eligible_for_ivl_eligibility_renewal(family, renewal_year)
          renewal_draft_applications = family.qhp_applications_for_year(renewal_year)
          return false if renewal_draft_applications.any? { |app| !app.is_initial? }

          return true if family.latest_application_type == 'qhp'

          fa_apps = ::FinancialAssistance::Application.only(:assistance_year, :family_id, :aasm_state).where(
            assistance_year: renewal_year, family_id: family.id
          )
          return false if fa_apps.empty?

          fa_apps.all? { |app| FA_APP_STATES.include?(app.aasm_state) }
        end

        # Generates an event for creating a renewal draft and publishes it
        #
        # @param family_id [String] the ID of the family for which to create the renewal draft
        # @param renewal_year [Integer] the year for which the renewal draft is created
        #
        # @return [Dry::Monads::Result] Success if the event is published, Failure with an error message otherwise
        def generate_event_and_publish(family_id, renewal_year)
          event(
            'events.individual_market.applications.renewal.create_renewal_draft',
            attributes: { family_id: family_id.to_s, renewal_year: renewal_year }
          ).success.publish
        end
      end
    end
  end
end
