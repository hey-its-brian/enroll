# frozen_string_literal: true

module Subscribers
  module FdshGateway
    # Subscriber will receive response payload from FDSH gateway
    # This subsriber is specific for hub calls
    class PvcMdcrDeterminationSubscriber
      include EventSource::Logging
      include ::EventSource::Subscriber[amqp: 'fdsh.pvc.medicare']
      include ::ResourceRegistryHelper

      subscribe(:on_periodic_verification_confirmation_determined) do |delivery_info, _metadata, response|
        logger.info "FdshGateway::PvcMdcrDeterminationSubscriber: invoked on_periodic_verification_confirmation_determined with delivery_info: #{delivery_info.inspect}, response: #{response.inspect}"
        fdsh_response = JSON.parse(response, :symbolize_names => true)

        logger.info "FdshGateway::PvcMdcrDeterminationSubscriber: parsed_response: #{fdsh_response.inspect}"
        result = if qhp_application_feature_enabled?
                   FinancialAssistance::Operations::Applications::Pvc::NonEsiEvidence::DetermineAndStoreResponse.new.call(fdsh_response)
                 else
                   FinancialAssistance::Operations::Applications::Pvc::Medicare::AddPvcMedicareDetermination.new.call(fdsh_response)
                 end

        if result.success?
          logger.info "FdshGateway::PvcMdcrDeterminationSubscriber: invoked on_periodic_verification_confirmation_determined acked with success: #{result.success}"
        else
          logger.info "FdshGateway::PvcMdcrDeterminationSubscriber: invoked on_periodic_verification_confirmation_determined acked with failure, errors: #{result.failure}"
        end
        ack(delivery_info.delivery_tag)
      rescue StandardError => e
        ack(delivery_info.delivery_tag)
        logger.error "FdshGateway::PvcMdcrDeterminationSubscriber: invoked on_periodic_verification_confirmation_determined error: #{e.message} // backtrace #{e.backtrace}"
      end
    end
  end
end
