# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module AsyncMigrations
    module Handlers
      module FAApplication
        # This Operation builds a new application for a given application identifier(BSON ID),
        class CopyWithoutPersisting < ::FinancialAssistance::Operations::Applications::Copy
          include Dry::Monads[:do, :result]
          include AddressValidator
          include I18n
          include ::ResourceRegistryHelper

          # Overrides the method to build a new application without persisting it.
          def copy_application(application, active_fms_applicant_params)
            draft_app = build_application(application, active_fms_applicant_params)

            if draft_app.valid?
              Success(draft_app)
            else
              # Log additional information
              simple_error_message = I18n.t('faa.errors.invalid_application')
              detailed_error_message = simple_error_message + " Errors: #{draft_app.errors.full_messages}"
              Failure(simple_error_message: simple_error_message, detailed_error_message: detailed_error_message)
            end
          rescue StandardError => e
            # Log additional information
            simple_error_message = I18n.t('faa.errors.copy_application_error')
            detailed_error_message = simple_error_message + " Error message: #{e.message}"
            Failure(simple_error_message: simple_error_message, detailed_error_message: detailed_error_message)
          end

          # Overrides the method to avoid persisting the new draft applicants.
          def update_claimed_as_tax_dependent_by(source_application, new_app)
            claimed_applicants = new_app.applicants.where(is_claimed_as_tax_dependent: true)
            claimed_applicants.each do |new_appl|
              new_appl.callback_update = true # avoiding callback to enroll in copy feature
              new_matching_applicant = claiming_applicant(source_application, new_appl)

              if new_matching_applicant.present?
                new_appl.claimed_as_tax_dependent_by = new_matching_applicant.id
              else
                @claiming_applicants_missing = true
              end
            end
          end

          # Overrides the method to avoid cancelling the applications without persisting the new draft application.
          def cancel_previous_applications(_draft_app)
            Success()
          end
        end
      end
    end
  end
end