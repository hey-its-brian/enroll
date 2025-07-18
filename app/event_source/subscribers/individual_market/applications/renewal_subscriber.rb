# frozen_string_literal: true

module Subscribers
  module IndividualMarket
    module Applications
      # Subscriber for handling renewal events in the individual market applications
      class RenewalSubscriber
        include ::EventSource::Subscriber[amqp: 'enroll.individual_market.applications.renewal']

        # Subscribes to the event for creating a renewal draft for each given family id
        subscribe(:on_create_renewal_draft) do |delivery_info, _metadata, response|
          sub_logger = Logger.new("#{Rails.root}/log/on_create_renewal_draft_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log")
          payload = JSON.parse(response, symbolize_names: true)
          # There is no PII in the payload, so it is safe to log.
          sub_logger.info "----- ocrd payload: #{payload}, delivery_info: #{delivery_info}"

          # TODO: Implement the logic to create a renewal draft
          # result = ::Operations::IndividualMarket::Applications::Renewal::CreateRenewalDraft.new.call(payload)
          # if result.success?
          #   sub_logger.info "--------------- ocrd Success. Message: #{result.success}"
          # else
          #   sub_logger.error "--------------- ocrd Failed. Message: #{result.failure}"
          # end

          ack(delivery_info.delivery_tag)
        rescue StandardError => e
          sub_logger.error "--------------- ocrd Errored. Message: #{e.message}, Backtrace: #{e.backtrace.join("\n")}"
          ack(delivery_info.delivery_tag)
        end

        # Subscribes to the event for submitting and determining renewal applications
        subscribe(:on_submit_and_determine) do |delivery_info, _metadata, response|
          sub_logger = Logger.new("#{Rails.root}/log/on_submit_and_determine_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log")
          payload = JSON.parse(response, symbolize_names: true)
          # There is no PII in the payload, so it is safe to log.
          sub_logger.info "----- osad payload: #{payload}, delivery_info: #{delivery_info}"

          # TODO: Implement the logic to submit and determine renewal applications
          # result = ::Operations::IndividualMarket::Applications::Renewal::SubmitAndDetermine.new.call(payload)
          # if result.success?
          #   sub_logger.info "--------------- osad Success. Message: #{result.success}"
          # else
          #   sub_logger.error "--------------- osad Failed. Message: #{result.failure}"
          # end

          ack(delivery_info.delivery_tag)
        rescue StandardError => e
          sub_logger.error "--------------- osad Errored. Message: #{e.message}, Backtrace: #{e.backtrace.join("\n")}"
          ack(delivery_info.delivery_tag)
        end
      end
    end
  end
end
