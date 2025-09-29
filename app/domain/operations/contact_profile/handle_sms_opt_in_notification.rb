# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module ContactProfile
    # Handle notification of an SMS number being opted-in (or back in) to communication.
    class HandleSmsOptInNotification
      include Dry::Monads[:do, :result, :try]
      include EventSource::Command

      def call(params)
        valid_params = yield validate_params(params)
        logger = valid_params[:logger]
        found_records = yield search_for_matching_records(valid_params[:phone])
        if found_records.empty?
          logger.info "No matching consumers found for opt in event on phone: #{valid_params[:phone]}"
          return Success(:ok)
        end
        enable_sms_messaging_preferences_for(found_records)
      end

      protected

      def enable_sms_messaging_preferences_for(found_records)
        return Success(:ok) unless EnrollRegistry.feature_enabled?(:enroll_sms_notifications)
        Try do
          found_records.each do |record|
            next unless record.consumer_role
            consumer_role = record.consumer_role
            next if consumer_role.can_receive_text_communication?
            contact_methods = consumer_role.current_contact_methods
            contact_methods << "Text"
            contact_methods.sort!
            consumer_role.contact_method = ConsumerRole::CONTACT_METHOD_MAPPING[contact_methods]
            consumer_role.save!
          end
        end.to_result
      end

      def validate_params(params)
        return Failure(:no_logger_provided) unless params[:logger]
        return Failure(:no_phone_provided) unless params[:phone]
        Success(params)
      end

      def search_for_matching_records(phone_number)
        ::Operations::ContactProfile::FindConsumersBySmsNumber.new.call(phone_number)
      end
    end
  end
end