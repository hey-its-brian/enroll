# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# ::Operations::DataFixes::CreateIndividualMarketEvidences.new.call({application_hbx_id: application_hbx_id})
module Operations
  module DataFixes
    # This operation creates Individual Market evidences.
    class CreateV3IndividualMarketEvidences < Operations::DataFixes::CreateV3Evidences
      include Dry::Monads[:do, :result]

      KEY_TITLE_TYPE_MAPPINGS = {'social_security_number_evidence' => [:social_security_number_evidence, 'Social Security Number Evidence', 'Eligibilities::V3::Evidences::SocialSecurityNumberEvidence'],
                                 'alive_evidence' => [:alive_evidence, 'Alive Evidence', 'Eligibilities::V3::Evidences::AliveEvidence'],
                                 'citizenship_evidence' => [:citizenship_evidence, 'Citizenship Evidence', 'Eligibilities::V3::Evidences::CitizenshipEvidence'],
                                 'american_indian_evidence' => [:american_indian_evidence, 'American Indian Evidence', 'Eligibilities::V3::Evidences::AmericanIndianEvidence'],
                                 'immigration_evidence' => [:immigration_evidence, 'Immigration Evidence', 'Eligibilities::V3::Evidences::ImmigrationEvidence']}.freeze

      def call(params)
        super
        result = yield create_ivl_evidences(@application)

        Success(result)
      end

      private

      def create_ivl_evidences(application)
        evidence_types = %w[
          social_security_number_evidence
          citizenship_evidence
          alive_evidence
          american_indian_evidence
          immigration_evidence
        ]

        result = application.applicants.flat_map do |applicant|
          person = applicant.family_member.person
          applicant_result = [
            application.family_id,
            application.hbx_id,
            application.aasm_state,
            application.created_at,
            application.primary_applicant.person_hbx_id,
            applicant.person_hbx_id,
            applicant.is_applying_coverage
          ]

          evidence_types.map do |evidence_type|
            map_applicant_evidence(applicant, person, applicant_result, evidence_type)
          end
        end

        Success(result)
      rescue StandardError => e
        Failure("Failed operation with error: #{e.message}")
      end

      def map_applicant_evidence(applicant, person, applicant_result, evidence_type)
        evidence = applicant.fetch_v3_evidence(evidence_type)
        return [*applicant_result, evidence_type, evidence.current_state, "applicant already has #{evidence_type}"] if evidence.present?

        evidence_not_created_reason = case evidence_type
                                      when 'social_security_number_evidence'
                                        handle_generate_v3_ssn_evidence(person, applicant_result)
                                      when 'alive_evidence'
                                        handle_generate_v3_alive_evidence(person, applicant_result)
                                      when 'citizenship_evidence'
                                        handle_generate_v3_citizenship_evidence(person, applicant_result)
                                      when 'american_indian_evidence'
                                        handle_generate_v3_ai_an_evidence(person, applicant_result)
                                      when 'immigration_evidence'
                                        handle_generate_v3_immigration_evidence(person, applicant_result)
                                      end

        return evidence_not_created_reason if evidence_not_created_reason.present?

        return determine_report_line(applicant, applicant_result, evidence_type) if @report

        new_evidence = create_ivl_evidence(applicant, *KEY_TITLE_TYPE_MAPPINGS[evidence_type])
        [*applicant_result, evidence_type, new_evidence.current_state, "successfully created #{evidence_type}"]
      end

      def handle_generate_v3_ssn_evidence(person, applicant_result)
        return if person.encrypted_ssn.present?

        [*applicant_result, 'social_security_number_evidence', '', "person does not have SSN, skipping social_security_number_evidence creation"]
      end

      def handle_generate_v3_alive_evidence(person, applicant_result)
        return if person&.is_applying_coverage && person.encrypted_ssn.present?

        [*applicant_result, 'alive_evidence', '', "person is not applying for coverage or is missing encrypted SSN, skipping alive_evidence creation"]
      end

      def handle_generate_v3_citizenship_evidence(person, applicant_result)
        return if person.citizen_status.in?([ConsumerRole::US_CITIZEN_STATUS, ConsumerRole::NATURALIZED_CITIZEN_STATUS])

        [*applicant_result, 'citizenship_evidence', '', "person is not a US/naturalized citizen, skipping citizenship_evidence creation"]
      end

      def handle_generate_v3_ai_an_evidence(person, applicant_result)
        return if person.indian_tribe_member.present?

        [*applicant_result, 'american_indian_evidence', '', "person is not a member of an Indian tribe, skipping american_indian_evidence creation"]
      end

      def handle_generate_v3_immigration_evidence(person, applicant_result)
        return if ConsumerRole::ALIEN_LAWFULLY_PRESENT_STATUS == person&.citizen_status

        [*applicant_result, 'immigration_evidence', '', "person does not have alien lawfully present status, skipping immigration_evidence creation"]
      end

      def create_ivl_evidence(applicant, key, title, type)
        applicant.build_individual_market_eligibility unless applicant.individual_market_eligibility.present?
        params = { key: key, title: title, _type: type, is_satisfied: true, current_state: 'unverified' }
        params[:current_state] = 'initial' if key == :alive_evidence

        evidence = applicant.individual_market_eligibility.evidences.build(params)

        if key == :alive_evidence
          update_reason = 'Data Migration - Alive evidence can only be moved to :outstanding or :attested by the DMF call'
          evidence.move_to_unverified(
            comment: 'Data Migration for post-V3 Evidence implementation Renewal Application',
            reason: update_reason
          )
        else
          update_reason = 'Data Migration - V3 Evidence Records'
          evidence.move_to_verified(
            comment: 'Data Migration for post-V3 Evidence implementation Renewal Application',
            reason: update_reason
          )
        end

        evidence.save!
        evidence
      end

      def determine_report_line(applicant, applicant_result, evidence_type)
        message = if applicant.individual_market_eligibility.present?
                    "#{evidence_type} not created - report mode enabled"
                  else
                    "individual_market_eligibility not found - #{evidence_type} not created"
                  end

        [*applicant_result, evidence_type, '', message]
      end
    end
  end
end
