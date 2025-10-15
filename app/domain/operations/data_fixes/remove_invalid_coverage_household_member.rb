# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# ::Operations::DataFixes::RemoveInvalidCoverageHouseholdMember.new.call({person_hbx_id: person_hbx_id})
module Operations
  module DataFixes
    # This operation removes invalid coverage household members.
    class RemoveInvalidCoverageHouseholdMember
      include Dry::Monads[:do, :result]

      def call(params)
        person_hbx_id = yield validate(params)
        person = yield fetch_person(person_hbx_id)
        yield validate_person(person)
        remove_chhm(person)
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
        return Failure("Person does not have a consumer role") unless person.consumer_role.present?
        return Failure("Person is not primary") unless person.primary_family.present?
        return Failure("Person is not an active member in any family") unless person.primary_family.active_family_members.present?

        Success(person)
      end

      def remove_chhm(person)
        family = person.primary_family
        family.active_household.coverage_households.each do |coverage_household|
          chhms = coverage_household.coverage_household_members
          valid_family_member_ids = family.active_family_members.map(&:id)
          chm_to_be_removed = chhms.where(:family_member_id.nin => valid_family_member_ids)

          next if chm_to_be_removed.empty?
          chm_to_be_removed.delete_all
        end

        Success("Successfully removed invalid coverage household members")
      rescue StandardError => e
        Failure("Failed to remove invalid coverage household members: #{e.message}")
      end
    end
  end
end
