# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# Syntax:
# Operations::People::BulkHubCallsForVerificationTypes.new.call({hbx_ids: [], verification_type_names: ["Social Security Number"]})
# Report
# Fetch the report from the root path bulk_hub_call_report_2021_09_29.csv
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
        csv_data = yield start(params)
        result = yield generate_csv(csv_data)

        Success(result)
      end

      private

      def validate(params)
        return Failure('No hbx_ids provided') if params[:hbx_ids].empty?
        return Failure('No verification_type_names provided') if params[:verification_type_names].empty?
        return Failure('Invalid verification_type_names provided') if params[:verification_type_names].any? { |v_type_name| RESTRICTED_VERIFICATION_TYPES.include?(v_type_name) }

        Success(params)
      end

      def start(params)
        hbx_ids = params[:hbx_ids]
        verification_type_names = params[:verification_type_names]

        people = Person.where(:hbx_id.in => hbx_ids)

        status = people.collect do |person|
          process_person(person, verification_type_names)
        end

        Success(status)
      end

      def process_person(person, verification_type_names)
        verification_types = person.verification_types.where(:type_name.in => verification_type_names)
        return [person.hbx_id, '', 'no verification types'] if verification_types.empty?

        verification_types.collect do |verification_type|
          process_verification_type(person, verification_type)
        end.flatten.compact
      end

      def process_verification_type(person, verification_type)
        return [person.hbx_id, verification_type.type_name, 'not eligible for hub call'] unless eligible_for_hub_call?(verification_type, person.consumer_role)

        verification_type.add_type_history_element(action: "Hub Request Initiated",
                                                   modifier: "Admin",
                                                   update_reason: "Bulk Hub Call")

        result = ::Operations::CallFedHub.new.call(
          person_id: person.id,
          verification_type: verification_type.type_name
        )

        handle_result(person, verification_type, result)
      end

      def eligible_for_hub_call?(verification_type, consumer_role)
        ELIGIBLE_FOR_HUB_CALL[verification_type.type_name][self, verification_type, consumer_role]
      end

      def handle_result(person, verification_type, result)
        _key, message = result.failure? ? result.failure : result.success
        if result.failure?
          verification_type.fail_type
          verification_type.add_type_history_element(
            action: "Hub Request Failed",
            modifier: "Admin",
            update_reason: "Bulk Process: #{verification_type.type_name} Request Failed due to #{message}"
          )
          person.families.each do |family|
            ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family, effective_date: TimeKeeper.date_of_record)
          end
        end

        [person.hbx_id, verification_type.type_name, message]
      end

      # Checks if the verification type is eligible for SSA
      #
      # @param verification_type [VerificationType] the verification type
      # @param consumer_role [ConsumerRole] the consumer role
      # @return [Boolean] whether the verification type is eligible for SSA
      def is_ssa_eligible?(verification_type, consumer_role)
        type_history_elements = verification_type.type_history_elements
        return false if type_history_elements.empty?
        event_response_record_id = type_history_elements.where(update_reason: "Hub response").order(created_at: :desc).first&.event_response_record_id
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

      def generate_csv(csv_data)
        field_names = %w[hbx_id verification_type message]
        file_name = "#{Rails.root}/bulk_hub_call_report_#{Date.today.strftime('%Y_%m_%d')}.csv"
        FileUtils.touch(file_name) unless File.exist?(file_name)

        CSV.open(file_name, 'w+', headers: true) do |csv|
          csv << field_names
          csv_data.each { |row| csv << row }
        end

        Success("Finished Bulk Hub Call, fetch the report from the root path #{file_name}")
      end
    end
  end
end