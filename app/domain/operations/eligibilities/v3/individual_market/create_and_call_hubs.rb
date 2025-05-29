# frozen_string_literal: true

module Operations
  module Eligibilities
    module V3
      module IndividualMarket
        # Creates an IVL eligibility with related evidences and calls respective hubs for each evidence.
        class CreateAndCallHubs
          include Dry::Monads[:do, :result]

          # @param application [FinancialAssistance::Application] The financial assistance application to process.
          #
          # @return [Dry::Monads::Result] Returns a Success with the application if successful, or a Failure with an error message.
          def call(application:)
            application = yield validate(application)
            application = yield build_ivl_eligibility_with_evidences(application)
            # application = yield call_respective_hubs(application)

            Success(application)
          end

          private

          # Validates that the provided application is of the correct type.
          # @param application [FinancialAssistance::Application] The application to validate.
          #
          # @return [Dry::Monads::Result] Returns a Success with the application if valid, or a Failure with an error message.
          def validate(application)
            if application.is_a?(::FinancialAssistance::Application)
              Success(application)
            else
              Failure("Invalid application type: #{application.class}")
            end
          end

          # Builds an IVL eligibility with evidences for the given application.
          # @param application [FinancialAssistance::Application] The application to process.
          #
          # @return [Dry::Monads::Result] Returns a Success with the application if successful, or a Failure with an error message.
          def build_ivl_eligibility_with_evidences(application)
            application.build_ivl_eligibility_with_evidences
            application.save!

            Success(application)
          rescue StandardError => e
            Rails.logger.error("QHP Application - Error while saving application with hbx_id: #{application.hbx_id}, error: #{e.message}, backtrace: #{e.backtrace.join("\n")}")
            Failure("Error while saving application with hbx_id: #{application.hbx_id} with error message: #{e.message}")
          end

          # # For each applicant we will call the operation to call hubs for each evidence.
          # # Each of these operations can be used as an admin's tool to call the respective hub.
          # def call_respective_hubs(application)
          # end
        end
      end
    end
  end
end
