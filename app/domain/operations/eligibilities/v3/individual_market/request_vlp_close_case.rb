# frozen_string_literal: true

module Operations
  module Eligibilities
    module V3
      module IndividualMarket
        # Request to close a case based on VLP determinations
        class RequestVlpCloseCase
          include Dry::Monads[:do, :result]
          include EventSource::Command

          def call(params)
            validated_params = yield validate_params(params)
            publish(validated_params)
            Success("Close case request published successfully")
          rescue StandardError => e
            Failure("Failed to publish close case request: #{e.message}")
          end

          private

          def validate_params(params)
            return Failure("Missing job_id") unless params[:job_id].present?
            return Failure("Missing correlation_id") unless params[:correlation_id].present?
            return Failure("Missing application_type") unless params[:application_type].present?
            return Failure("Missing determinations") unless params[:determinations].present?
            return Failure('no VLP determinations found') unless params[:determinations].key?("vlp") && params[:determinations]["vlp"].present?

            Success(params)
          end

          def publish(values)
            headers = {job_id: values[:job_id], application_hbx_id: values[:correlation_id], application_type: values[:application_type]}
            event = event('events.enroll.verifications.ssa_vlp.close_case.requested', attributes: values[:determinations].slice("vlp"), headers: headers).value!
            event.publish
          end
        end
      end
    end
  end
end