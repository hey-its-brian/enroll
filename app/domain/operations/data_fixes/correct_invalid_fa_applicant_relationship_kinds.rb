# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module DataFixes
    # ActionType: 'data_fix'
    #   This operation corrects invalid FA applicant relationship kinds.
    #   Also, destroys the relationships if the kind is self.
    # ActionType: 'report'
    #   This operation generates a report of invalid FA applicant relationships.
    #   Also, includes relationships with kind self in the report.
    class CorrectInvalidFaApplicantRelationshipKinds
      include Dry::Monads[:do, :result]

      def call(params)
        applications = yield fetch_applications
        result = yield generate_report_or_fix_data(params[:action_type], applications)

        Success(result)
      end

      private

      # Fetch applications with invalid relationship kinds
      #
      # @return [Dry::Monads::Result]
      def fetch_applications
        Success(
          ::FinancialAssistance::Application.all.only(
            :hbx_id, :relationships, :id, :family_id, :aasm_state, :assistance_year, :transfer_id
          ).where(
            :relationships => {
              '$elemMatch' => {
                :kind => {'$nin' => AcaEntities::MagiMedicaid::Types::RelationshipKind.values},
                :_id => {'$exists' => true}
              }
            }
          )
        )
      end

      # Method to figure out whether to generate report or fix data based on action type
      #
      # @param [String] action_type
      # @param [Mongoid::Criteria] applications
      #
      # @return [Dry::Monads::Result]
      def generate_report_or_fix_data(action_type, applications)
        case action_type
        when 'data_fix'
          fix_invalid_relationship_kinds(applications)
          Success("Data fix completed. Report generated: #{@csv_file}")
        when 'report'
          generate_report(applications)
          Success("Report generated: #{@csv_file}")
        else
          Failure("Invalid action type: #{action_type}. Please provide either 'data_fix' or 'report'.")
        end
      end

      # Method to generate a report of invalid FA applicant relationships
      #
      # @param [Mongoid::Criteria] applications
      #
      # @return [void]
      def generate_report(applications)
        @csv_file = "invalid_fa_applicant_relationship_kinds_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv"
        CSV.open(@csv_file, 'w', force_quotes: true) do |csv|
          csv << [
            'Primary Person Hbx ID',
            'FA Application Hbx ID',
            'FA Application Assistance Year',
            'FA Application AASM State',
            'FA Application Transfer ID',
            'Applicant ID',
            'Relative ID',
            'Invalid Relationship Kind'
          ]

          applications.each do |application|
            application.relationships.where(:kind.nin => PersonRelationship::Relationships_UI).each do |relationship|
              family = Family.only(:family_members, :id).where(id: application.family_id).first
              primary_person = Person.only(:hbx_id, :id, :is_tobacco_user).where(id: family.primary_applicant.person_id).first

              csv << [
                primary_person.hbx_id,
                application.hbx_id,
                application.assistance_year,
                application.aasm_state,
                application.transfer_id,
                relationship.applicant_id,
                relationship.relative_id,
                relationship.kind
              ]
            end
          end
        end
      end

      # Method to fix invalid FA applicant relationship kinds
      # If the relationship kind is 'self', the relationship is destroyed.
      # Otherwise, the relationship kind is updated to 'other'.
      #
      # @param [Mongoid::Criteria] applications
      #
      # @return [void]
      def fix_invalid_relationship_kinds(applications)
        @csv_file = "invalid_fa_applicant_relationship_kinds_data_fix_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv"
        CSV.open(
          @csv_file, 'w', force_quotes: true
        ) do |csv|
          csv << [
            'Primary Person Hbx ID',
            'FA Application Hbx ID',
            'FA Application Assistance Year',
            'FA Application AASM State',
            'FA Application Transfer ID',
            'Applicant ID',
            'Relative ID',
            'Invalid Relationship Kind',
            'Action Taken'
          ]

          applications.each do |application|
            application.relationships.where(:kind.nin => PersonRelationship::Relationships_UI).each do |relationship|
              family = Family.only(:family_members, :id).where(id: application.family_id).first
              primary_person = Person.only(:hbx_id, :id, :is_tobacco_user).where(id: family.primary_applicant.person_id).first

              if relationship.kind == 'self'
                relationship.delete
                action_taken = 'Destroyed relationship'
              else
                old_kind = relationship.kind
                relationship.set(kind: 'unrelated')
                action_taken = "Updated from #{old_kind} to unrelated"
              end

              csv << [
                primary_person.hbx_id,
                application.hbx_id,
                application.assistance_year,
                application.aasm_state,
                application.transfer_id,
                relationship.applicant_id,
                relationship.relative_id,
                relationship.kind,
                action_taken
              ]
            end
          end
        end
      end
    end
  end
end
