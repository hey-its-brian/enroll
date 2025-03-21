# frozen_string_literal: true

module Operations
  module Families
    module Verifications
      module Summary
        # Shared functionality to find subject and member records based on family and person_id
        module SubjectMemberFinder
          extend ActiveSupport::Concern
          include Dry::Monads[:result]

          # Find the eligibility subject for the given person_id within a family
          #
          # @param family [Family] the family containing the subject
          # @param person_id [String] the ID of the person to find
          # @return [Result] success with subject or failure with error message
          def find_subject(family:, person_id:)
            subject = family.eligibility_determination.subjects.by_person(person_id).first
            return Failure("Subject not found") unless subject.present?

            Success(subject)
          end

          # Find the family member associated with a subject
          #
          # @param family [Family] the family containing the member
          # @param subject [EligibilitySubject] the subject to find the member for
          # @return [Result] success with member or failure with error message
          def find_member(family:, subject:)
            member = family.find_family_member_by_person(subject.person)
            return Failure("Member not found") unless member.present?

            Success(member)
          end
        end
      end
    end
  end
end
