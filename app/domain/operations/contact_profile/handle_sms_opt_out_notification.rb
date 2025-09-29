# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module ContactProfile
    # Handle notification of an SMS number being opted-out of communication
    class HandleSmsOptOutNotification
      include Dry::Monads[:do, :result, :try]
      include EventSource::Command

      def call(params)
        valid_params = yield validate_params(params)
        logger = valid_params[:logger]
        found_records = yield search_for_matching_records(valid_params[:phone])
        if found_records.empty?
          logger.info "No matching consumers found for opt out event on phone: #{valid_params[:phone]}"
          return Success(:ok)
        end
        disable_sms_messaging_preferences_for(found_records, logger)
      end

      protected

      def disable_sms_messaging_preferences_for(found_records, logger)
        return Success(:ok) unless EnrollRegistry.feature_enabled?(:enroll_sms_notifications)
        Try do
          found_records.each do |record|
            next unless record.consumer_role
            consumer_role = record.consumer_role
            next unless consumer_role.can_receive_text_communication?
            existing_contact_methods = consumer_role.current_contact_methods
            new_contact_methods = existing_contact_methods - ["Text"]
            if new_contact_methods.empty?
              has_email = !consumer_role.email.blank?
              has_mail = !consumer_role.mailing_address.blank?
              if has_email
                consumer_role.contact_method = ConsumerRole::CONTACT_METHOD_MAPPING[["Email"]]
              elsif has_mail
                consumer_role.contact_method = ConsumerRole::CONTACT_METHOD_MAPPING[["Mail"]]
              else
                logger.error "Matched individual #{record.id} has no other available methods of contact, not opting out."
                next
              end
            else
              consumer_role.contact_method = ConsumerRole::CONTACT_METHOD_MAPPING[new_contact_methods]
            end
            record.save!
          end
          :ok
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