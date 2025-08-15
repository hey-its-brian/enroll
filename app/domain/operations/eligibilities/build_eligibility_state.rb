# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Eligibilities
    # Build Eligibility state for the eligibility item passed
    class BuildEligibilityState
      include Dry::Monads[:do, :result]
      include ::ResourceRegistryHelper
      include LoggingHelper

      # @param [Hash] opts Options to build eligibility state
      # @option opts [GlobalID] :subject required
      # @option opts [AcaEntities::Eligibilities::EligibilityItem] :eligibility_item required
      # @option opts [Array<Symbol>] :evidence_item_keys optional
      # @return [Dry::Monad] result
      def call(params)
        @logger = yield initialize_logger
        values = yield validate(params)
        eligibility_state = yield build_eligibility_state(values)

        Success(eligibility_state)
      end

      private

       # Initializes the daily log file
      def initialize_logger
        Success(
          Logger.new(
            "#{Rails.root}/log/build_eligibility_state_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
          )
        )
      rescue StandardError => e
        Failure("Error initializing logger: #{e.message}")
      end


      def validate(params)
        errors = []
        errors << 'subject missing' unless params[:subject]
        errors << 'eligibility item missing' unless params[:eligibility_item]
        @family = params[:family]

        errors.empty? ? Success(params) : Failure(errors)
      end

      def evidence_items_for(values)
        eligibility_item = values[:eligibility_item]

        eligibility_item.evidence_items.select do |evidence_item|
          values[:evidence_item_keys].blank? ||
            values[:evidence_item_keys].include?(evidence_item.key.to_sym)
        end
      end

      def evidence_states_for(values)
        evidence_items_for(values)
          .collect do |evidence_item|
            attrs = values.slice(:subject, :eligibility_item).merge(evidence_item: evidence_item)
            attrs.merge!(family: @family)

            @logger.info("Calling BuildEvidenceState for Evidence Key: #{evidence_item.key}")
            result = Operations::Eligibilities::BuildEvidenceState.new.call(attrs)
            @logger.info("BuildEvidenceState result for #{evidence_item.key}: #{result.success? ? 'SUCCESS' : "FAILURE - #{result.failure}"}")

            result.success? ? result.success : {}
          end
          .compact
          .reduce(:merge)
      end

      def build_eligibility_state(values)
        evidence_states = evidence_states_for(values)
        evidence_states.delete_if do |_evidence_key, evidence_state|
          evidence_state.empty?
        end

        eligibility_state = {
          determined_at: DateTime.now,
          evidence_states: evidence_states
        }

        if values[:eligibility_item].key == 'aptc_csr_credit'
          subject = GlobalID::Locator.locate(values[:subject])
          grants = build_csr_grants(subject).success

          # Builds MagiMedicaid Grants for aptc_csr_credit if QHP application feature is enabled
          if qhp_application_feature_enabled?
            mm_grants = construct_magi_medicaid_grants_params(subject).success
            grants += mm_grants if mm_grants.present?
          end

          eligibility_state.merge!(grants: grants)
        end

        # Builds QHP Grants for aca_individual_market_eligibility if QHP application feature is enabled
        if qhp_application_feature_enabled? && values[:eligibility_item].key == 'aca_individual_market_eligibility'
          subject = GlobalID::Locator.locate(values[:subject])
          grants = construct_qhp_grants_params(subject).success

          eligibility_state.merge!(grants: grants)
        end

        if evidence_states.present?
          eligibility_state.merge!(
            {
              is_eligible: fetch_status(evidence_states),
              earliest_due_date: fetch_earliest_due_date(evidence_states),
              document_status: fetch_document_status(evidence_states)
            }
          )
        end

        Success(eligibility_state)
      end

      def build_csr_grants(family_member)
        Operations::Eligibilities::BuildGrant.new.call(
          family_member: family_member,
          family: family_member.family,
          type: 'CsrAdjustmentGrant'
        )
      end

      # Constructs MagiMedicaid Grants for the latest active tax household group for all the assistance years
      # Tax household Members are found based on the tax household member's applicant_id is equal to family_member.id
      #
      # @param [FamilyMember] family_member
      # @return [Dry::Monads::Result] Success with array of MagiMedicaid grant params or Failure with error message
      def construct_magi_medicaid_grants_params(family_member)
        ::Operations::Eligibilities::BuildGrant.new.call(
          family: family_member.family, family_member: family_member, type: 'MagiMedicaidGrant'
        )
      end

      # Constructs QHP Grants for the latest active tax household group for all the assistance years
      # Tax household Members are found based on the tax household member's applicant_id is equal to family_member.id
      #
      # @param [FamilyMember] family_member
      # @return [Dry::Monads::Result] Success with array of QHP grant params or Failure with error message
      def construct_qhp_grants_params(family_member)
        ::Operations::Eligibilities::BuildGrant.new.call(
          family: family_member.family, family_member: family_member, type: 'QhpGrant'
        )
      end

      def fetch_document_status(evidence_states)
        evidence_statuses = evidence_states.values.collect { |evidence_state| evidence_state[:status].to_s }
        non_verified_states = evidence_statuses.reject {|status| ['verified', 'attested', 'determined'].include?(status)}

        return 'NA' if non_verified_states.blank?
        return 'Fully Uploaded' if non_verified_states.all?{|status| status == 'review'}
        return 'Partially Uploaded' if non_verified_states.include?('review')
        return 'None' if evidence_statuses.include?('outstanding')

        'NA'
      end

      def fetch_earliest_due_date(evidence_states)
        evidence_to_compare = evidence_states.values.reject{|value| value[:due_on].blank?}
        return nil if evidence_to_compare.empty?

        evidence_to_compare.min_by do |evidence_state|
          evidence_state[:due_on]
        end[
          :due_on
        ]
      end

      def fetch_status(evidence_states)
        evidence_states.values.all? do |evidence_state|
          evidence_state[:is_satisfied]
        end
      end
    end
  end
end
