# frozen_string_literal: true

module Subscribers
  # Subscriber for assister hired or fired events
  class AssisterUpdatesSubscriber
    include ::EventSource::Subscriber[amqp: 'enroll.family.assisters']

    subscribe(:on_assister_hired) do |delivery_info, _metadata, response|
      subscriber_logger = subscriber_logger_for(:on_enroll_family_assister_hired)
      payload = JSON.parse(response, symbolize_names: true)
      subscriber_logger.info "AssisterUpdatesSubscriber, response: #{payload}"
      hire_assister(payload, subscriber_logger)

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "AssisterUpdatesSubscriber, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      subscriber_logger.error "AssisterUpdatesSubscriber, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    subscribe(:on_assister_fired) do |delivery_info, _metadata, response|
      subscriber_logger = subscriber_logger_for(:on_enroll_family_assister_fired)
      payload = JSON.parse(response, symbolize_names: true)
      subscriber_logger.info "AssisterUpdatesSubscriber, response: #{payload}"
      fire_assister(payload, subscriber_logger)

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "AssisterUpdatesSubscriber, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      subscriber_logger.error "AssisterUpdatesSubscriber, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    def hire_assister(payload, subscriber_logger)
      ::Operations::Families::HireAssisterAgency.new.call(payload)
    rescue StandardError => e
      subscriber_logger.error "Error: AssisterUpdatesSubscriber, error message: #{e.message}, backtrace: #{e.backtrace}"
    end

    def fire_assister(payload, subscriber_logger)
      ::Operations::Families::TerminateAssisterAgency.new.call(payload)
    rescue StandardError => e
      subscriber_logger.error "Error: AssisterUpdatesSubscriber, error message: #{e.message}, backtrace: #{e.backtrace}"
    end

    def subscriber_logger_for(event)
      Logger.new(
        "#{Rails.root}/log/#{event}_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
      )
    end
  end
end
