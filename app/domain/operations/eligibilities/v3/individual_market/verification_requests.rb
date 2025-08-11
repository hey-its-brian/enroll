# frozen_string_literal: true

module Operations
  module Eligibilities
    module V3
      module IndividualMarket
        # Orchestrates the process of requesting various verification services for an application
        #
        # This operation serves as a coordinator for multiple verification services.
        # Currently, it handles SSA VLP (Social Security Administration Verification of Lawful Presence)
        # verification requests, but can be extended to support additional verification types.
        #
        # @example Processing verification requests for an application
        #   result = Operations::Eligibilities::V3::IndividualMarket::VerificationRequests.new.call(
        #     application: financial_assistance_application
        #   )
        #
        #   if result.success?
        #     puts "Verification requests processed successfully"
        #   else
        #     puts "Failed to process verification requests: #{result.failure}"
        #   end
        class VerificationRequests
          include Dry::Monads[:do, :result]

          # Processes verification requests for the given application
          #
          # @param application [FinancialAssistance::Application] The application to process verifications for
          # @return [Dry::Monads::Result::Success] On successful processing with the application
          # @return [Dry::Monads::Result::Failure] On processing failure with error message
          def call(application:)
            application = yield validate(application)
            _app_entity = yield build_app_entity(application)
            call_ssa_vlp(application)

            Success(application)
          end

          private

          # Validates that the provided application is of the correct type
          #
          # @param application [Object] The application to validate
          # @return [Dry::Monads::Result::Success] If the application is of a supported type
          # @return [Dry::Monads::Result::Failure] If the application is of an unsupported type
          def validate(application)
            if application.is_a?(::FinancialAssistance::Application) || application.is_a?(::IndividualMarket::Application)
              Success(application)
            else
              Failure("Invalid application type: #{application.class}")
            end
          end

          # Builds the application entity required for verification services
          #
          # Uses the Fdsh BuildAndValidateApplicationPayload operation to create the
          # standardized application entity representation needed by verification services.
          #
          # @param application [FinancialAssistance::Application] The application to build an entity from
          # @return [Dry::Monads::Result::Success] Always returns success as the actual entity is stored in @application_entity
          def build_app_entity(application)
            @application_entity = if application.is_a?(::FinancialAssistance::Application)
                                    Operations::Fdsh::BuildAndValidateApplicationPayload.new.call(application)
                                  else
                                    Operations::Fdsh::BuildAndValidateUqhpApplicationPayload.new.call(application)
                                  end
            Success(nil)
          end

          # Initiates an SSA VLP verification request for the application
          #
          # Delegates to the SsaVlpVerification operation to handle the specifics
          # of the verification request process.
          #
          # @param application [FinancialAssistance::Application] The application to verify
          # @return [Dry::Monads::Result::Success] Always returns success regardless of underlying operation result
          def call_ssa_vlp(application)
            Operations::Eligibilities::V3::IndividualMarket::SsaVlpVerification.new.call(entity_result: @application_entity,
                                                                                         application: application,
                                                                                         call_type: 'application_determination')
            Success(nil)
          end
        end
      end
    end
  end
end
