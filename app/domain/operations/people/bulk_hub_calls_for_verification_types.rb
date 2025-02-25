# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module People
    # Bulk FedHubCalls for verification types
    class BulkHubCallsForVerificationTypes
      include Dry::Monads[:do, :result]

      ELIGIBLE_FOR_HUB_CALL = {
        VerificationType::SOCIAL_SECURITY_NUMBER => ->(instance, v_type, consumer_role) { instance.is_ssa_eligible?(v_type, consumer_role) },
        VerificationType::CITIZENSHIP => ->(instance, v_type, consumer_role) { instance.is_ssa_eligible?(v_type, consumer_role) }
      }.freeze

      RESTRICTED_VERIFICATION_TYPES = [
        VerificationType::IMMIGRATION_STATUS,
        VerificationType::AMERICAN_INDIAN_STATUS,
        VerificationType::ALIVE_STATUS
      ].freeze

      # Initiates bulk FedHub calls for verification types
      #
      # @param params [Hash] the parameters for the operation
      # @option params [Array<String>] :hbx_ids the HBX IDs of the people to verify
      # @option params [Array<String>] :verification_type_names the names of the verification types
      # @return [Dry::Monads::Result] the result of the operation
      def call(params)
        params = yield validate(params)
        result = yield start(params)

        Success(result)
      end

      private

      def validate(params)
        return Failure('No hbx_ids provided') if params[:hbx_ids].empty?
        return Failure('No verification_type_names provided') if params[:verification_type_names].empty?
        return Failure('Invalid verification_type_names provided') if params[:verification_type_names].any?{|v_type_name| RESTRICTED_VERIFICATION_TYPES.include?(v_type_name)}

        Success(params)
      end

      def start(params)
        hbx_ids = params[:hbx_ids]
        verification_type_names = params[:verification_type_names]

        people = Person.where(:hbx_id.in => hbx_ids)

        status = people.collect do |person|
          verification_types = person.verification_types.where(:type_name.in => verification_type_names)
          next [person.hbx_id, '','no verification types'] if verification_types.empty?

          result = verification_types.collect do |verification_type|
            next [person.hbx_id, verification_type.type_name, 'not eligible for hub call'] unless ELIGIBLE_FOR_HUB_CALL[verification_type.type_name][self, verification_type, person.consumer_role]

            result = ::Operations::CallFedHub.new.call(
              person_id: person.id,
              verification_type: verification_type.type_name
            )

            _key, message = result.failure? ? result.failure : result.success
            if result.failure?
              verification_type.fail_type
              verification_type.add_type_history_element(action: "Hub Request Failed",
                                                         modifier: "System",
                                                         update_reason: "#{verification_type.type_name} Request Failed due to #{message}")
              person.families.each do |family|
                ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family, effective_date: TimeKeeper.date_of_record)
              end
            end

            [person.hbx_id, verification_type.type_name, message]
          end
          result.flatten.compact
        end

        Success(status)
      end

      # Checks if the verification type is eligible for SSA
      #
      # @param verification_type [VerificationType] the verification type
      # @param consumer_role [ConsumerRole] the consumer role
      # @return [Boolean] whether the verification type is eligible for SSA
      def is_ssa_eligible?(verification_type, consumer_role)
        type_history_elements = verification_type.type_history_elements
        return false if type_history_elements.empty?
        event_response_record_id = type_history_elements.order(created_at: :desc).first&.event_response_record_id
        return false unless event_response_record_id

        response = consumer_role.lawful_presence_determination.ssa_responses.where(id: BSON::ObjectId.from_string(event_response_record_id))
        return false unless response.present?

        payload = JSON.parse(response.first.body, symbolize_names: true)
        ssa_response = payload.dig(:SSACompositeIndividualResponses, 0, :SSAResponse)
        response_code = payload.dig(:ResponseMetadata, :ResponseCode)
        return false unless response_code == "HS000000" && ssa_response.present?

        ssn_verification_indicator = ssa_response[:SSNVerificationIndicator]
        citizenship_verification_indicator = ssa_response[:PersonUSCitizenIndicator]
        ssn_verification_indicator && citizenship_verification_indicator
      end
    end
  end
end
