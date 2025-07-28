# frozen_string_literal: true

module Subscribers
  # Subscriber will receive batch process requests
  class BatchProcessSubscriber
    include ::EventSource::Subscriber[amqp: "enroll.batch_process.events"]

    subscribe(
      :on_batch_events_requested
    ) do |delivery_info, _metadata, response|
      logger.info "-" * 100 unless Rails.env.test?

      payload = JSON.parse(response, symbolize_names: true)

      subscriber_logger =
        Logger.new(
          "#{Rails.root}/log/on_on_batch_events_requested_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
        )

      subscriber_logger.info "BatchProcessSubscriber, response: #{payload}"
      logger.info "BatchProcessSubscriber payload: #{payload}" unless Rails.env.test?

      batch_handler = payload[:batch_handler].constantize
      batch_handler.new(payload).trigger_batch_requests

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "BatchProcessSubscriber, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      logger.error "BatchProcessSubscriber: errored & acked. error message: #{e.message}, Backtrace: #{e.backtrace}"
      subscriber_logger.error "BatchProcessSubscriber, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    subscribe(
      :on_batch_event_process_requested
    ) do |delivery_info, _metadata, response|
      logger.info "-" * 100 unless Rails.env.test?

      payload = JSON.parse(response, symbolize_names: true)

      subscriber_logger =
        Logger.new(
          "#{Rails.root}/log/on_batch_event_process_requested_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
        )

      subscriber_logger.info "BatchProcessSubscriber#on_enroll_enterprise_events, response: #{payload}"
      logger.info "BatchProcessSubscriber#on_enroll_enterprise_events payload: #{payload}" unless Rails.env.test?

      batch_handler = payload[:batch_handler].constantize
      batch_handler.new(payload).process_batch_request(payload[:batch_options])

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "BatchProcessSubscriber#on_enroll_enterprise_events, payload: #{payload}, error_message: #{e.message}, backtrace: #{e.backtrace}"
      logger.error "BatchProcessSubscriber#on_enroll_enterprise_events: errored & acked. error_message: #{e.message}, Backtrace: #{e.backtrace}"
      subscriber_logger.error "BatchProcessSubscriber#on_enroll_enterprise_events, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    subscribe(:on_request_migration_event_batches) do |delivery_info, _metadata, response|
      logger.info "-" * 100 unless Rails.env.test?

      subscriber_logger =
        Logger.new(
          "#{Rails.root}/log/on_request_migration_event_batches_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
        )

      payload = JSON.parse(response, symbolize_names: true)

      subscriber_logger.info "BatchProcessSubscriber, response: #{payload}"
      logger.info "BatchProcessSubscriber payload: #{payload}" unless Rails.env.test?

      batch_requestor = ::Operations::AsyncMigrations::BatchRequestor.new
      result = batch_requestor.call(payload)
      if result.success?
        if result.success.is_a?(Array)
          result.success.each do |message|
            subscriber_logger.info "BatchProcessSubscriber, #{batch_requestor.class} result: #{message}"
            logger.info "BatchProcessSubscriber, #{batch_requestor.class} result: #{message}" unless Rails.env.test?
          end
        else
          subscriber_logger.info "BatchProcessSubscriber, #{batch_requestor.class} result: #{result.success}"
          logger.info "BatchProcessSubscriber, #{batch_requestor.class} result: #{result.success}" unless Rails.env.test?
        end
      else
        subscriber_logger.error "BatchProcessSubscriber, #{batch_requestor.class} result: #{result.failure}"
        logger.error "BatchProcessSubscriber, #{batch_requestor.class} result: #{result.failure}" unless Rails.env.test?
      end

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "BatchProcessSubscriber, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      logger.error "BatchProcessSubscriber: errored & acked. error message: #{e.message}, Backtrace: #{e.backtrace}"
      subscriber_logger.error "BatchProcessSubscriber, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    subscribe(:on_process_migration_event_batches) do |delivery_info, _metadata, response|
      logger.info "-" * 100 unless Rails.env.test?

      subscriber_logger =
        Logger.new(
          "#{Rails.root}/log/on_process_migration_event_batches_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
        )

      payload = JSON.parse(response, symbolize_names: true)

      subscriber_logger.info "BatchProcessSubscriber, response: #{payload}"
      logger.info "BatchProcessSubscriber payload: #{payload}" unless Rails.env.test?

      batch_handler = ::Operations::AsyncMigrations::BatchProcessor.new
      result = batch_handler.call(payload)
      if result.success?
        subscriber_logger.info "BatchProcessSubscriber, #{batch_handler.class} result: #{result.success}"
        logger.info "BatchProcessSubscriber, #{batch_handler.class} result: #{result.success}" unless Rails.env.test?
      else
        subscriber_logger.error "BatchProcessSubscriber, #{batch_handler.class} result: #{result.failure}"
        logger.error "BatchProcessSubscriber, #{batch_handler.class} result: #{result.failure}" unless Rails.env.test?
      end

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "BatchProcessSubscriber, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      logger.error "BatchProcessSubscriber: errored & acked. error message: #{e.message}, Backtrace: #{e.backtrace}"
      subscriber_logger.error "BatchProcessSubscriber, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    subscribe(:on_process_migration_event) do |delivery_info, _metadata, response|
      logger.info "-" * 100 unless Rails.env.test?

      subscriber_logger =
        Logger.new(
          "#{Rails.root}/log/on_process_migration_event_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
        )

      payload = JSON.parse(response, symbolize_names: true)

      subscriber_logger.info "BatchProcessSubscriber, response: #{payload}"
      logger.info "BatchProcessSubscriber payload: #{payload}" unless Rails.env.test?

      migration_handler_name = payload[:migration_handler_name]
      migration_handler_class = ::Operations::AsyncMigrations::Mappings::EVENT_HANDLER_MAP[migration_handler_name]
      raise "No string-to-class mapping found for #{migration_handler_name}" unless migration_handler_class.present?
      migration_handler = migration_handler_class.new
      raise "#{migration_handler.class} is not a domain operation that responds to #call" unless migration_handler.respond_to?(:call)

      result = migration_handler.call(payload)
      if result.success?
        subscriber_logger.info "BatchProcessSubscriber, #{migration_handler.class} result: #{result.success}"
        logger.info "BatchProcessSubscriber, #{migration_handler.class} result: #{result.success}" unless Rails.env.test?
      else
        subscriber_logger.error "BatchProcessSubscriber, #{migration_handler.class} result: #{result.failure}"
        logger.error "BatchProcessSubscriber, #{migration_handler.class} result: #{result.failure}" unless Rails.env.test?
      end

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "BatchProcessSubscriber, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      logger.error "BatchProcessSubscriber: errored & acked. error message: #{e.message}, Backtrace: #{e.backtrace}"
      subscriber_logger.error "BatchProcessSubscriber, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end
  end
end
