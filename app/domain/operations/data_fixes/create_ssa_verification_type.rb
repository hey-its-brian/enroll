# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# ::Operations::DataFixes::CreateSsaVerificationType.new.call({person_hbx_id: person_hbx_id})
module Operations
  module DataFixes
    # This operation creates SSA verification type.
    class CreateSsaVerificationType
      include Dry::Monads[:do, :result]

      def call(params)
        person_hbx_id = yield validate(params)
        person = yield fetch_person(person_hbx_id)
        yield validate_person(person)
        create_verification_type(person)
      end

      private

      def validate(params)
        return Failure("person_hbx_id is missing") unless params[:person_hbx_id].present?

        Success(params[:person_hbx_id])
      end

      def fetch_person(person_hbx_id)
        ::Operations::People::Find.new.call({person_hbx_id: person_hbx_id})
      end

      def validate_person(person)
        return Failure("Person SSN is not present to create SSA verification type") unless person.encrypted_ssn.present?
        return Failure("Person does not have a consumer role") unless person.consumer_role.present?
        return Failure("Person is not associated with any family") unless person.families.present?
        return Failure("Person is not an active member in any family") unless person.families.collect {|f| f.active_family_members.where(person_id: person.id).present? }.any?
        return Failure("Person SSA verification type is already present") if person.verification_types.unscoped.ssn_type.present?

        Success(person)
      end

      def create_verification_type(person)
        verification_type = person.verification_types.create(
          type_name: VerificationType::SOCIAL_SECURITY_NUMBER,
          validation_status: "unverified"
        )

        verification_type.assign_attributes(validation_status: "verified")

        update_reason = "Data Migration - Evidence Records"
        params = {action: "Data Migration", update_reason: update_reason, modifier: "Admin", from_validation_status: "unverified", to_validation_status: "verified"}
        verification_type.save!
        verification_type.type_history_elements.create(params)

        person.families.each do |family|
          ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
        end

        Success("Successfully created verification type")
      rescue StandardError => e
        Failure("Failed to create verification type: #{e.message}")
      end
    end
  end
end
