# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module DataFixes
    # ActionType: 'data_fix'
    #   This operation corrects invalid person relationship kinds.
    #   Also, destroys the relationships if the kind is self.
    # ActionType: 'report'
    #   This operation generates a report of invalid person relationships.
    #   Also, includes relationships with kind self in the report.
    class CorrectInvalidPersonRelationshipKinds
      include Dry::Monads[:do, :result]

      def call(params)
        people = yield fetch_people
        result = yield generate_report_or_fix_data(params[:action_type], people)

        Success(result)
      end

      private

      # Fetch people with invalid person relationship kinds
      #
      # @return [Dry::Monads::Result]
      def fetch_people
        Success(
          ::Person.all.only(:hbx_id, :person_relationships, :id, :is_tobacco_user).where(
            :person_relationships => {
              '$elemMatch' => {
                :kind => {'$nin' => ::PersonRelationship::Relationships_UI},
                :_id => {'$exists' => true}
              }
            }
          )
        )
      end

      # Method to figure out whether to generate report or fix data based on action type
      #
      # @param [String] action_type
      # @param [Mongoid::Criteria] people
      #
      # @return [Dry::Monads::Result]
      def generate_report_or_fix_data(action_type, people)
        case action_type
        when 'data_fix'
          fix_invalid_relationship_kinds(people)
          Success("Data fix completed. Report generated: #{@csv_file}")
        when 'report'
          generate_report(people)
          Success("Report generated: #{@csv_file}")
        else
          Failure("Invalid action type: #{action_type}. Please provide either 'data_fix' or 'report'.")
        end
      end

      # Method to generate a report of invalid person relationships
      #
      # @param [Mongoid::Criteria] people
      #
      # @return [void]
      def generate_report(people)
        @csv_file = "invalid_person_relationship_kinds_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv"
        CSV.open(@csv_file, 'w', force_quotes: true) do |csv|
          csv << [
            'Primary Person Hbx ID',
            'Dependent Person Hbx ID',
            'Invalid Relationship Kind'
          ]

          people.each do |person|
            person.person_relationships.where(
              :kind.nin => ::PersonRelationship::Relationships_UI
            ).each do |relationship|
              relative = Person.where(id: relationship.relative_id).first
              next if relative.blank?

              csv << [
                person.hbx_id,
                relative.hbx_id,
                relationship.kind
              ]
            end
          end
        end
      end

      # Method to fix invalid person relationship kinds
      # If the relationship kind is 'self', the relationship is destroyed.
      # Otherwise, the relationship kind is updated to 'other'.
      #
      # @param [Mongoid::Criteria] people
      #
      # @return [void]
      def fix_invalid_relationship_kinds(people)
        @csv_file = "invalid_person_relationship_kinds_data_fix_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv"
        CSV.open(
          @csv_file, 'w', force_quotes: true
        ) do |csv|
          csv << [
            'Primary Person Hbx ID',
            'Dependent Person Hbx ID',
            'Invalid Relationship Kind',
            'Action Taken'
          ]

          people.each do |person|
            invalid_relationships = person.person_relationships.where(:kind.nin => ::PersonRelationship::Relationships_UI)

            invalid_relationships.each do |relationship|
              relative = Person.where(id: relationship.relative_id).first
              next if relative.blank?

              if relationship.kind == 'self'
                relationship.delete
                action = 'Destroyed relationship'
              else
                old_kind = relationship.kind
                relationship.set(kind: 'unrelated')
                action = "Updated from #{old_kind} to unrelated"
              end

              csv << [
                person.hbx_id,
                relative.hbx_id,
                relationship.kind,
                action
              ]
            end
          end
        end
      end
    end
  end
end
