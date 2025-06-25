# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module People
    # This class is to Trigger all Person OnUpdate events.
    #   1. Determine Verifications(SSA/VLP)
    class OnUpdate
      include Dry::Monads[:do, :result]

      def call(params)
        params                  = yield validate_params(params)
        consumer_role           = yield fetch_consumer_role(params)
        determine_verifications(consumer_role, params[:payload])
      end

      private

      def validate_params(params)
        return Failure("Invalid parameters, missing gid for #{params}") if params[:gid].blank?
        return Failure("Invalid parameters, missing payload for #{params}") unless params[:payload].is_a?(Hash)

        Success(params)
      end

      def fetch_consumer_role(params)
        gid = params[:gid]
        consumer_role = GlobalID::Locator.locate(gid).consumer_role
        return Failure("ConsumerRole not found for gid: #{gid}") unless consumer_role.present?

        Success(consumer_role)
      end

      def determine_verifications(consumer_role, changes)
        return Success(nil) unless attributes_changed?(changes)

        ::Operations::Individual::DetermineVerifications.new.call({id: consumer_role.id})
      end

      def attributes_changed?(changes)
        attested_no_ssn = changes.dig(:no_ssn, 0) == '0' # if old value is '0' then it means no_ssn is now attested

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
    end
  end
end
