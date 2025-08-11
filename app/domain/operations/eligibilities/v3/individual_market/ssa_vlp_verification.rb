# frozen_string_literal: true

module Operations
  module Eligibilities
    module V3
      module IndividualMarket
        # Publishes an SSA VLP (Social Security Administration Verification of Lawful Presence)
        # verification request for a given application.
        #
        # This operation handles the complete workflow of creating a verification job,
        # preparing the application data, transmitting the request to external verification
        # systems, and recording the request details for audit and tracking purposes.
        #
        # @example Publishing an SSA VLP verification request
        #   result = Operations::Eligibilities::V3::IndividualMarket::SsaVlpVerification.new.call(
        #     application: financial_assistance_application
        #   )
        #
        #   if result.success?
        #     puts "Request submitted: #{result.value!}"
        #   else
        #     puts "Request failed: #{result.failure}"
        #   end
        class SsaVlpVerification
          include Dry::Monads[:do, :result]
          include ::Operations::Transmittable::TransmittableUtils
          include EventSource::Command

          # Evidences that are eligible for SSA VLP verification
          EVIDENCE_KEYS = %w[social_security_number_evidence citizenship_evidence immigration_evidence].freeze

          # Processes an SSA VLP verification request for the given application
          #
          # @param params [Hash] Parameters for the operation
          # @option params [FinancialAssistance::Application] :application The application to verify
          # @option params [Hash, nil] :application_entity Optional pre-built application entity
          #
          # @return [Dry::Monads::Result::Success] On successful submission with confirmation message
          # @return [Dry::Monads::Result::Failure] On failure with error message
          def call(params)
            @application = yield validate(params)
            transmittable_params = yield build_transmittable_params
            @job = yield create_job(transmittable_params)
            @request_transmission = yield build_and_create_request_transmission(transmittable_params)
            @request_transaction = yield build_and_create_request_transaction(transmittable_params)
            @app_entity = yield build_app_entity(params)
            publish(params)
          end

          private

          # Validates that the provided application is of the correct type.
          # @param application [FinancialAssistance::Application] The application to validate.
          # @return [Dry::Monads::Result] Returns a Success with the application if valid, or a Failure with an error message.
          def validate(params)
            return Failure('call type not specified') unless params[:call_type]

            @call_type = params[:call_type]
            @updated_by = params[:updated_by] || 'System'
            application = params[:application]
            if application.is_a?(::FinancialAssistance::Application) || application.is_a?(::IndividualMarket::Application)
              Success(application)
            else
              Failure("Invalid application type: #{application.class}")
            end
          end

          # Builds the base parameters used across job, transmission, and transaction records
          #
          # @return [Dry::Monads::Result::Success] Contains the base parameter hash with common values
          def build_transmittable_params
            hbx_id = @application.hbx_id
            values = {
              key: :ssa_vlp_verification_request,
              title: "SSA VLP verification Request",
              description: "SSA VLP verification call for application with hbx_id #{hbx_id}",
              correlation_id: hbx_id,
              transmission_id: hbx_id,
              transaction_id: hbx_id,
              started_at: DateTime.now,
              publish_on: DateTime.now,
              event: 'initial',
              state_key: :initial
            }

            Success(values)
          end

          # Creates a request transmission record to track the SSA VLP verification request
          #
          # @param values [Hash] The base parameter values for the transmission
          # @return [Transmittable::Transmission] The created request transmission record
          def build_and_create_request_transmission(values)
            values[:job] = @job

            create_request_transmission(values, @job)
          end

          # Creates a request transaction record to track the individual transmission attempt
          #
          # @param values [Hash] The base parameter values for the transaction
          # @return [Transmittable::Transaction] The created request transaction record
          def build_and_create_request_transaction(values)
            values[:transmission] = @request_transmission
            values[:subject] = @application

            create_request_transaction(values, @job)
          end

          # Builds the application entity for transmission to external systems
          #
          # Uses either the provided application entity or creates one via the
          # BuildAndValidateApplicationPayload operation.
          #
          # @param params [Hash] Operation parameters containing optional application_entity
          # @return [Dry::Monads::Result::Success] On successful entity creation with the entity data
          # @return [Dry::Monads::Result::Failure] On entity validation or creation failure
          #
          # @raise [StandardError] On unexpected errors during entity building
          def build_app_entity(params)
            result = if params[:entity_result].present?
                       params[:entity_result]
                     elsif @application.is_a?(::FinancialAssistance::Application)
                       Operations::Fdsh::BuildAndValidateApplicationPayload.new.call(@application)
                     else
                       Operations::Fdsh::BuildAndValidateUqhpApplicationPayload.new.call(@application)
                     end
            if result.success?
              @request_transaction.json_payload = result.value!.to_h
              @request_transaction.save
              Success(@request_transaction.json_payload)
            else
              add_errors(
                :build_app_entity,
                "Payload failed validation due to #{result.failure}",
                { job: @job, transmission: @request_transmission, transaction: @request_transaction }
              )
              status_result = update_status("Payload failed validation", :failed, { job: @job, transmission: @request_transmission, transaction: @request_transaction })
              return status_result if status_result.failure?
              add_verification_histories(update_reason: 'Request failed due to invalid payload')
              Failure("Failed to build application entity")
            end
          rescue StandardError => e
            add_errors(
              :build_app_entity,
              "Error occurred while building application entity: #{e.message}",
              { job: @job, transmission: @request_transmission, transaction: @request_transaction }
            )
            status_result = update_status("Error occurred while building application entity", :failed, { job: @job, transmission: @request_transmission, transaction: @request_transaction })
            return status_result if status_result.failure?
            Failure("Failed to build application entity")
          end

          # Publishes the SSA VLP verification event to the message queue
          #
          # @return [Dry::Monads::Result::Success] On successful publication with confirmation message
          # @return [Dry::Monads::Result::Failure] On publication failure with error message
          #
          # @raise [StandardError] On unexpected errors during event publication
          def publish(params)
            headers = {
              job_id: @job&.job_id,
              application_type: @application.is_a?(::FinancialAssistance::Application) ? 'faa' : 'uqhp',
              key: :ssa_vlp_verification_request,
              correlation_id: @application.hbx_id,
              call_type: @call_type
            }
            # for admin call hub requests, we need to pass the requested ids
            headers.merge!(request_hbx_ids: params[:request_hbx_ids]) if params[:request_hbx_ids].present?

            event = event('events.enroll.verifications.ssa_vlp.requested', attributes: @app_entity.to_h, headers: headers).success
            event.publish
            status_result = update_status("published SSA VLP verification request", :transmitted, { job: @job, transmission: @request_transmission, transaction: @request_transaction })
            return status_result if status_result.failure?
            add_verification_histories(update_reason: 'Hub Request was made due to demographics created/update')
            Success("SSA VLP verification request for Application with hbx_id #{@application.hbx_id} is submitted")
          rescue StandardError => e
            add_errors(
              :publish,
              "Error occurred while publishing SSA VLP verification request: #{e.message}",
              { job: @job, transmission: @request_transmission, transaction: @request_transaction }
            )
            status_result = update_status("Error occurred while publishing SSA VLP verification request", :failed, { job: @job, transmission: @request_transmission, transaction: @request_transaction })
            return status_result if status_result.failure?
            Failure("Failed to publish SSA VLP verification request")
          end

          def add_verification_histories(update_reason)
            # matching current behavior
            update_reason = @call_type == 'application determination' ? update_reason : nil
            @application.applicants.each do |applicant|
              eligibility = applicant.eligibilities.detect {|eli| eli.key.to_s == 'individual_market_eligibility' }
              next unless eligibility
              evidences = eligibility.evidences.select {|e| EVIDENCE_KEYS.include?(e.key.to_s) }
              evidences.each do |evidence|
                evidence.verification_histories.build({
                                                        action: "SSA VLP Hub Request",
                                                        update_reason: update_reason,
                                                        updated_by: @updated_by
                                                      })
              end
              @application.save
            end
          end
        end
      end
    end
  end
end
