# frozen_string_literal: true

module Subscribers
  # Subscriber will receive request payload from EA to generate a renewal draft application
  class PeopleSubscriber
    include EventSource::Logging
    include ::EventSource::Subscriber[amqp: 'enroll.people']

    subscribe(:on_person_saved) do |delivery_info, _metadata, response|
      subscriber_logger = subscriber_logger_for(:on_person_saved)
      payload = JSON.parse(response, symbolize_names: true)
      pre_process_message(subscriber_logger, payload)
      # Add subscriber operations below this line
      redetermine_family_eligibility(payload)

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "PeopleSubscriber::Save, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      subscriber_logger.error "PeopleSubscriber::Save, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    subscribe(:on_person_updated) do |delivery_info, _metadata, response|
      subscriber_logger = subscriber_logger_for(:on_person_updated)
      payload = JSON.parse(response, symbolize_names: true)
      pre_process_message(subscriber_logger, payload)

      determine_verifications(payload, subscriber_logger) if !Rails.env.test? && EnrollRegistry.feature_enabled?(:consumer_role_hub_call)

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "PeopleSubscriber::Update, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      subscriber_logger.error "PeopleSubscriber::Update,  ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    subscribe(:on_person_inbox_message_received) do |delivery_info, _metadata, response|
      payload = JSON.parse(response, symbolize_names: true)
      Operations::People::HandleInboxMessageReceived.new.call(payload)
      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      logger.error "PeopleSubscriber::PersonInboxMessageReceived, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      logger.error "PeopleSubscriber::PersonInboxMessageReceived, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    def redetermine_family_eligibility(payload)
      return if EnrollRegistry.feature_enabled?(:qhp_application)

      person = GlobalID::Locator.locate(payload[:gid])

      person.families.each do |family|
        ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
      end
    end

    def determine_verifications(payload, subscriber_logger)
      result = ::Operations::People::OnUpdate.new.call(
        { gid: payload[:gid] }
      )

      if result.success?
        success = result.success
        subscriber_logger.info "PeopleSubscriber::Update, determine_verifications result: Success: #{success}" if success.present?
      else
        subscriber_logger.info "PeopleSubscriber::Update, determine_verifications result: Failure: #{result.failure}"
      end
    rescue StandardError => e
      subscriber_logger.error "Error: PeopleSubscriber::Update, error message: #{e.message}, backtrace: #{e.backtrace}"
    end

    private

    def pre_process_message(subscriber_logger, payload)
      subscriber_logger.info "PeopleSubscriber, response: #{payload}"
    end

    def subscriber_logger_for(event)
      Logger.new(
        "#{Rails.root}/log/#{event}_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
      )
    end
  end
end
