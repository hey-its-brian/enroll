# frozen_string_literal: true

module Subscribers
  module FdshGateway
  # Subscriber will receive response payload from FDSH gateway
    class SsaVlpverificationsSubscriber
      include EventSource::Logging
      include ::EventSource::Subscriber[amqp: 'fdsh.verifications.ssavlp']

      subscribe(:on_determined) do |delivery_info, metadata, response|
        logger.info "SsaVlpverificationsSubscriber: invoked on_ssa_vlp_verification_determined with delivery_info: #{delivery_info.inspect}, response: #{response.inspect}"
        job_id = metadata[:headers]["job_id"]
        correlation_id = metadata[:correlation_id]
        application_type = metadata[:headers]["application_type"]
        call_type = metadata[:headers]["call_type"]
        determinations = metadata[:headers]["determined_applicants"]
        status = metadata[:headers]["status"]

        if status == "failure"
          handle_failure_response(job_id)
          logger.info "Ssa::SsaVlpverificationsSubscriber: on_determined acked and processed failure from fdsh_gateway"
        else
          verification_payload = { application_hbx_id: correlation_id, job_id: job_id,
                                   response: response, app_type: application_type, determinations: determinations,
                                   call_type: call_type }
          result = Operations::Eligibilities::V3::IndividualMarket::SsaVlpDetermined.new.call(verification_payload)
          if result.success?
            trigger_close_case_request(job_id, determinations, correlation_id, application_type)
            logger.info "Ssa::SsaVlpverificationsSubscriber: on_determined acked with success: #{result.success}"
          elsif result.failure
            errors = result.failure
            logger.info "Ssa::SsaVlpverificationsSubscriber: on_determined acked with failure, errors: #{errors}"
          end
        end
        ack(delivery_info.delivery_tag)
      rescue StandardError => e
        ack(delivery_info.delivery_tag)
        logger.error "SsaVlpverificationsSubscriber: on_determined error_message: #{e.message}, backtrace: #{e.backtrace}"
      end

      def trigger_close_case_request(job_id, determinations, correlation_id, application_type)
        return unless EnrollRegistry.feature_enabled?(:send_close_case_request)

        headers = {job_id: job_id, application_hbx_id: correlation_id, application_type: application_type}
        event = event('events.enroll.verifications.ssavlp.closecase.requested', attributes: determinations.slice(:vlp), headers: headers)
        event.publish
      end

      def handle_failure_response(job_id)
        return unless job_id
        job = Transmittable::Job.where(job_id: job_id)&.last
        return unless job
        message = "Job failed in FDSH Gateway"
        Operations::Transmittable::UpdateProcessStatus.new.call({ transmittable_objects: { job: job }, state: :failed, message: message })
        Operations::Transmittable::AddError.new.call({ transmittable_objects: { job: job }, key: :fdsh_gateway, message: message })
      end
    end
  end
end
