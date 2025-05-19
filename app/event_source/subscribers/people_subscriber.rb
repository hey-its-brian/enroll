# frozen_string_literal: true

module Subscribers
  # Subscriber will receive request payload from EA to generate a renewal draft application
  class PeopleSubscriber
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

    def redetermine_family_eligibility(payload)
      person = GlobalID::Locator.locate(payload[:gid])

      person.families.each do |family|
        ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
      end
    end

    def determine_verifications(params, subscriber_logger)
      person = GlobalID::Locator.locate(params[:gid])
      consumer_role = person.consumer_role

      if consumer_role.present? && attributes_changed?(params[:payload])
        result = ::Operations::Individual::DetermineVerifications.new.call({id: consumer_role.id})
        result_str = result.success? ? "Success: #{result.success}" : "Failure: #{result.failure}"
        subscriber_logger.info "PeopleSubscriber::Update, determine_verifications result: #{result_str}"
      end
    rescue StandardError => e
      subscriber_logger.error "Error: PeopleSubscriber::Update, error message: #{e.message}, backtrace: #{e.backtrace}"
    end

    private

    def attributes_changed?(changes)
      attested_no_ssn = changes[:no_ssn][0] == '0' # if old value is '0' then it means no_ssn is now attested

      # only check for tribe status attribute changes if the changes hash contains a non-empty value
      # @note it is possible for the  tribe status attributes to update from an empty string to nil, so we need to discard that case
      # @see Person#indian_tribe_member=, Person#indian_tribe_member, and Person#check_indian
      tribe_status_attributes = EnrollRegistry[:consumer_role_hub_call].setting(:indian_tribe_attributes).item.map(&:to_sym)
      tribe_status_attributes_changes = tribe_status_attributes.map { |attr| changes[attr] }.compact
      tribe_status_attribute_changed = tribe_status_attributes_changes.any? do |tribe_status_attribute_change|
        tribe_status_attribute_change[0].present? || tribe_status_attribute_change[1].present?
      end

      # for the identifying information attributes, we just simply check if any have changed
      identifying_information_attributes = EnrollRegistry[:consumer_role_hub_call].setting(:identifying_information_attributes).item.map(&:to_sym)
      identifying_information_attributes_changed = (identifying_information_attributes & changes.keys).present?

      attested_no_ssn || tribe_status_attribute_changed || identifying_information_attributes_changed.present?
    end

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
