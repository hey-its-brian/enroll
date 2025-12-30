# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module DataFixes
    # ActionType: 'data_fix'
    #   This operation corrects invalid applicant relationship kinds for both
    #   FinancialAssistance::Application and IndividualMarket::Application.
    #   Also, destroys the relationships if the kind is self.
    # ActionType: 'report'
    #   This operation generates a report of invalid applicant relationships for both
    #   FinancialAssistance::Application and IndividualMarket::Application.
    #   Also, includes relationships with kind self in the report.
    #
    # @param params [Hash]
    # @option params [String] :action_type ('report', 'data_fix') - Type of action to perform
    # @option params [String] :type ('individual_market', 'financial_assistance', 'both') - Type of applications to fetch
    class CorrectInvalidApplicantRelationshipKinds
      include Dry::Monads[:do, :result]

      VALID_TYPES = %w[individual_market financial_assistance both].freeze

      def call(params)
        validated_params = yield validate_params(params)
        applications = yield fetch_applications(validated_params[:type])
        result = yield generate_report_or_fix_data(validated_params[:action_type], applications)

        Success(result)
      end

      private

      # Validates input parameters
      #
      # @param params [Hash]
      # @return [Dry::Monads::Result]
      def validate_params(params)
        action_type = params[:action_type]
        type = params[:type] || 'both'

        return Failure("Invalid action type: #{action_type}. Please provide either 'data_fix' or 'report'.") unless %w[data_fix report].include?(action_type)

        return Failure("Invalid type: #{type}. Please provide 'individual_market', 'financial_assistance', or 'both'.") unless VALID_TYPES.include?(type)

        Success(action_type: action_type, type: type)
      end

      # Fetch applications with invalid relationship kinds based on type parameter
      #
      # @param type [String] Type of applications to fetch
      # @return [Dry::Monads::Result]
      def fetch_applications(type)
        all_applications = []

        if %w[individual_market both].include?(type)
          individual_market_applications = ::IndividualMarket::Application.all.only(
            :hbx_id, :relationships, :id, :family_id, :current_state, :assistance_year
          ).where(
            :relationships => {
              '$elemMatch' => {
                :kind => {'$nin' => PersonRelationship::Relationships_UI},
                :_id => {'$exists' => true}
              }
            }
          )
          all_applications += individual_market_applications.to_a
        end

        if %w[financial_assistance both].include?(type)
          financial_assistance_applications = ::FinancialAssistance::Application.all.only(
            :hbx_id, :relationships, :id, :family_id, :aasm_state, :assistance_year, :transfer_id
          ).where(
            :relationships => {
              '$elemMatch' => {
                :kind => {'$nin' => PersonRelationship::Relationships_UI},
                :_id => {'$exists' => true}
              }
            }
          )
          all_applications += financial_assistance_applications.to_a
        end

        Success(all_applications)
      end

      # Method to figure out whether to generate report or fix data based on action type
      #
      # @param [String] action_type
      # @param [Array<FinancialAssistance::Application, IndividualMarket::Application>] applications
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
        end
      end

      # Method to generate a report of invalid applicant relationships
      #
      # @param [Array] applications
      #
      # @return [void]
      def generate_report(applications)
        @csv_file = "invalid_applicant_relationship_kinds_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv"
        CSV.open(@csv_file, 'w', force_quotes: true) do |csv|
          csv << [
            'Primary Person Hbx ID',
            'Application Hbx ID',
            'Application Type',
            'Application Assistance Year',
            'Application State',
            'Application Transfer ID',
            'Applicant/Source ID',
            'Relative ID',
            'Invalid Relationship Kind'
          ]

          applications.each do |application|
            application.relationships.where(:kind.nin => PersonRelationship::Relationships_UI).each do |relationship|
              family = Family.only(:family_members, :id).where(id: application.family_id).first
              primary_person = Person.only(:hbx_id, :id, :is_tobacco_user).where(id: family.primary_applicant.person_id).first

              # Handle both IndividualMarket::Relationship (source_id) and FinancialAssistance::Relationship (applicant_id)
              applicant_or_source_id = relationship.respond_to?(:applicant_id) ? relationship.applicant_id : relationship.source_id

              # Determine application type and handle different field names
              is_individual_market = application.is_a?(::IndividualMarket::Application)
              app_type = is_individual_market ? 'IndividualMarket::Application' : 'FinancialAssistance::Application'
              app_state = is_individual_market ? application.current_state : application.aasm_state
              transfer_id = is_individual_market ? nil : application.transfer_id

              csv << [
                primary_person.hbx_id,
                application.hbx_id,
                app_type,
                application.assistance_year,
                app_state,
                transfer_id,
                applicant_or_source_id,
                relationship.relative_id,
                relationship.kind
              ]
            end
          end
        end
      end

      # Method to fix invalid applicant relationship kinds
      # If the relationship kind is 'self', the relationship is destroyed.
      # Otherwise, the relationship kind is updated to 'unrelated'.
      #
      # @param [Array] applications
      #
      # @return [void]
      def fix_invalid_relationship_kinds(applications)
        @csv_file = "invalid_applicant_relationship_kinds_data_fix_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv"
        CSV.open(
          @csv_file, 'w', force_quotes: true
        ) do |csv|
          csv << [
            'Primary Person Hbx ID',
            'Application Hbx ID',
            'Application Type',
            'Application Assistance Year',
            'Application State',
            'Application Transfer ID',
            'Applicant/Source ID',
            'Relative ID',
            'Invalid Relationship Kind',
            'Action Taken'
          ]

          applications.each do |application|
            application.relationships.where(:kind.nin => PersonRelationship::Relationships_UI).each do |relationship|
              family = Family.only(:family_members, :id).where(id: application.family_id).first
              primary_person = Person.only(:hbx_id, :id, :is_tobacco_user).where(id: family.primary_applicant.person_id).first

              # Handle both IndividualMarket::Relationship (source_id) and FinancialAssistance::Relationship (applicant_id)
              applicant_or_source_id = relationship.respond_to?(:applicant_id) ? relationship.applicant_id : relationship.source_id

              # Determine application type and handle different field names
              is_individual_market = application.is_a?(::IndividualMarket::Application)
              app_type = is_individual_market ? 'IndividualMarket::Application' : 'FinancialAssistance::Application'
              app_state = is_individual_market ? application.current_state : application.aasm_state
              transfer_id = is_individual_market ? nil : application.transfer_id

              old_kind = relationship.kind

              if relationship.kind == 'self'
                relationship.delete
                action_taken = 'Destroyed relationship'
              else
                relationship.set(kind: 'unrelated')
                action_taken = "Updated from #{old_kind} to unrelated"
              end

              csv << [
                primary_person.hbx_id,
                application.hbx_id,
                app_type,
                application.assistance_year,
                app_state,
                transfer_id,
                applicant_or_source_id,
                relationship.relative_id,
                old_kind,
                action_taken
              ]
            end
          end
        end
      end
    end
  end
end
