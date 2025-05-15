# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    module Application
      # Operation to create a new Individual Market Application with associated applicants
      # Uses dry-monads for result handling and validation
      class Create
        include Dry::Monads[:do, :result]

        ELIGIBILITY_CLASSES = {
          individual_market_eligibility: ::Eligibilities::V3::IndividualMarketEligibility,
          aptc_csr_eligibility: ::Eligibilities::V3::AptcCsrEligibility
        }.freeze

        # Creates a new Individual Market Application with associated applicants
        # @param params [Hash] The parameters for creating the application
        # @option params [Hash] :applicants Array of applicant information
        # @return [Dry::Monads::Result] Returns Success(application_id) or Failure(errors)
        def call(params:)
          values = yield validate(params)
          create(values)
        end

        private

        # Validates the input parameters using Application Contract
        # @param params [Hash] The parameters to validate
        # @return [Dry::Monads::Result] Returns Success(validated_hash) or Failure(validation_errors)
        def validate(params)
          result = ::Validators::IndividualMarket::ApplicationContract.new.call(params)

          if result.success?
            Success(result.to_h)
          else
            Failure(result)
          end
        end

        # Creates the application and its associated applicants
        # @param values [Hash] The validated parameters
        # @return [Dry::Monads::Result] Returns Success(application_id) or Failure(errors)
        def create(values)
          application = ::IndividualMarket::Application.new(values.except(:applicants))

          applicants_results = values[:applicants].map do |applicant|
            ::Operations::IndividualMarket::Applicant::Build.new.call(params: applicant.merge(application: application))
          end

          applicants_results.map do |result|
            if result.success?
              applicant_params = result.success.to_h
              applicant = application.applicants.build
              applicant.assign_attributes(applicant_params.except(:eligibilities))
              build_eligibilities(applicant, applicant_params[:eligibilities])
            else
              result.failure
            end
          end

          build_relationships(application)

          if application.save
            Success(application.id)
          else
            Failure(application.errors)
          end
        end

        # Builds eligibility records for an applicant
        # @param applicant [IndividualMarket::Applicant] The applicant to build eligibilities for
        # @param eligibilities [Array<Hash>] Array of eligibility parameters
        # @option eligibilities [Symbol] :key The type of eligibility
        # @option eligibilities [String] :title The display title for the eligibility
        # @return [void]
        def build_eligibilities(applicant, eligibilities)
          eligibilities.each do |eligibility|
            eligibility_class = ELIGIBILITY_CLASSES[eligibility[:key]]
            next unless eligibility_class

            applicant.eligibilities.build(eligibility.merge(_type: eligibility_class))
          end
        end

        # Builds relationship records between primary applicant and dependents
        # @param application [IndividualMarket::Application] The application containing the applicants
        # @return [void]
        # @note Relationships are only built for non-primary applicants who have a defined relationship
        #   to the primary applicant through their family member record
        def build_relationships(application)
          primary_applicant = application.primary_applicant

          application.non_primary_applicants.each do |applicant|
            next unless applicant.family_member&.relationship

            relationships_params = {
              source_id: applicant.id,
              relative_id: primary_applicant.id,
              kind: applicant.family_member.relationship
            }

            application.relationships.build(relationships_params)
          end
        end
      end
    end
  end
end
