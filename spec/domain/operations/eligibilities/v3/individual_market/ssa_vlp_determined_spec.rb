# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/shared_contexts/valid_cv3_application_setup.rb')

RSpec.describe ::Operations::Eligibilities::V3::IndividualMarket::SsaVlpDetermined, type: :model, dbclean: :after_each do
  include_context "valid cv3 application setup"

  before :all do
    DatabaseCleaner.clean
  end
  let(:subject) { described_class.new }
  let(:rr) do
    { result: 'test_state',
      source: "FDSH SSA",
      code: 'HS000000',
      code_description: 'SSA VLP Determined',
      raw_payload: "{\"ResponseMetadata\":{\"ResponseCode\":\"HS000000\",\"ResponseText\":\"Success\"},\"SSACompositeIndividualResponses\":[{\"SSAResponse\":{\"SSNVerificationIndicator\":true,\"PersonUSCitizenIndicator\":false}}]}"}
  end

  let(:immigration_rr) do
    { result: 'test_state',
      source: "FDSH VLP",
      code: 'HS000000',
      code_description: 'SSA VLP Determined',
      raw_payload: "{\"ResponseMetadata\":{\"ResponseCode\":\"HS000000\",\"ResponseDescriptionText\":\"Successful.\"},
      \"InitialVerificationResponseSet\":{\"InitialVerificationIndividualResponses\":[{\"ResponseMetadata\":{\"ResponseCode\":\"HS000000\",
      \"ResponseDescriptionText\":\"Successful.\"},\"LawfulPresenceVerifiedCode\":\"P\",\"InitialVerificationIndividualResponseSet\":{\"CaseNumber\":\"0000000000000AA\",\"NonCitLastName\":\"NonCitLastName1\",
      \"NonCitFirstName\":\"NonCitFirstName1\",\"NonCitMiddleName\":null,\"NonCitBirthDate\":\"2006-05-04T00:00:00.000Z\",\"NonCitEntryDate\":null,\"AdmittedToDate\":null,\"AdmittedToText\":null,
      \"NonCitCountryBirthCd\":null,\"NonCitCountryCitCd\":null,\"NonCitCoaCode\":null,\"NonCitProvOfLaw\":null,\"NonCitEadsExpireDate\":null,\"EligStatementCd\":5,\"EligStatementTxt\":\"EligStatementTxt1\",
      \"IAVTypeCode\":null,\"IAVTypeTxt\":null,\"WebServSftwrVer\":\"WebServSftwrVer1\",\"GrantDate\":null,\"GrantDateReasonCd\":null,\"SponsorDataFoundIndicator\":null,\"ArrayOfSponsorshipData\":null,
      \"SponsorshipReasonCd\":null,\"AgencyAction\":\"AgencyAction1\",\"FiveYearBarApplyCode\":\"N\",\"QualifiedNonCitizenCode\":\"N\",\"FiveYearBarMetCode\":\"N\",\"USCitizenCode\":\"N\"}}]}}"}
  end

  let(:eligibility_hash) do
    {:key => "individual_market_eligibility",
     :evidences => [{:key => "social_security_number_evidence",
                     :request_results => [rr],:current_state => :attested},
                    {:key => "citizenship_evidence", :request_results => [rr], :current_state => :outstanding},
                    {:key => "immigration_evidence", :request_results => [immigration_rr], :current_state => :outstanding}]}
  end

  let!(:job) do
    job = FactoryBot.create(:transmittable_job, key: :ssa_vlp_determined, job_id: "test1234")
    job.process_status = FactoryBot.create(:transmittable_process_status, statusable: job)
    job.process_status.process_states << FactoryBot.create(:transmittable_process_state, process_status: job.process_status)
    job.save
    job
  end

  describe '#call' do
    before do
      @application_hash = Operations::Fdsh::BuildAndValidateApplicationPayload.new.call(application).value!.to_h
      @determinations = application.applicants.pluck(:person_hbx_id)
      application.applicants.each do |applicant|
        applicant.build_ivl_eligibility_with_evidences
        individual_market_eligibility = applicant.individual_market_eligibility
        # Creating both citizenship and immigration evidences for testing.
        individual_market_eligibility.evidences.build(
          _type: 'Eligibilities::V3::Evidences::CitizenshipEvidence',
          title: 'Citizenship Evidence',
          key: :citizenship_evidence,
          current_state: :pending
        )
        individual_market_eligibility.evidences.build(
          _type: 'Eligibilities::V3::Evidences::ImmigrationEvidence',
          title: 'Immigration Evidence',
          key: :immigration_evidence,
          current_state: :pending
        )
        applicant.save
      end
    end

    context 'with valid application' do
      before do
        @application_hash[:applicants].each do |applicant|
          applicant[:eligibilities] = [eligibility_hash]
        end
        @result = subject.call({call_type: 'application_determination', job_id: job.job_id, application_hbx_id: @application_hash[:hbx_id],
                                response: @application_hash.to_json, app_type: 'faa',
                                determinations: {ssa: @determinations, vlp: @determinations}})
      end

      it 'returns success with message' do
        expect(@result).to be_success
        expect(::Transmittable::Job.first.process_status.latest_state).to eq(:succeeded)
        expect(::Transmittable::Transmission.first.process_status.latest_state).to eq(:succeeded)
        expect(::Transmittable::Transaction.first.process_status.latest_state).to eq(:succeeded)
      end

      it 'creates request results for each evidence' do
        application.reload
        applicant = application.applicants.first
        individual_market_eligibility = applicant.individual_market_eligibility

        ssn_evidence = individual_market_eligibility.evidences.detect { |e| e.key.to_sym == :social_security_number_evidence }

        expect(ssn_evidence.request_results.count).to eq(1)
        expect(ssn_evidence.request_results.first.result).to eq('test_state')
        expect(ssn_evidence.request_results.first.source).to eq('FDSH SSA')
        expect(ssn_evidence.request_results.first.code).to eq('HS000000')
      end

      it 'updates consumer role lawful presence determination' do
        application.reload
        applicant = application.applicants.first
        expect(applicant.five_year_bar_applies).to eq false
        expect(applicant.five_year_bar_met).to eq false
        expect(applicant.qualified_non_citizen).to eq false
        expect(applicant.citizenship_result).to eq 'not_lawfully_present_in_us'
      end

      context 'when evidence current_state is attested' do
        let(:ssn_eligibility_hash) do
          {key: "individual_market_eligibility",
           evidences: [{key: "social_security_number_evidence",
                        request_results: [rr], current_state: :attested}]}
        end
        let(:params) do
          {call_type: 'application_determination', job_id: job.job_id, application_hbx_id: @application_hash[:hbx_id],
           response: @application_hash.to_json, app_type: 'faa',
           determinations: {ssa: @determinations, vlp: @determinations}}
        end

        before do
          @application_hash[:applicants].each do |applicant|
            applicant[:eligibilities] = [ssn_eligibility_hash]
          end
        end

        it 'marks evidence as verified' do
          application.reload
          applicant = application.applicants.first
          individual_market_eligibility = applicant.individual_market_eligibility
          ssn_evidence = individual_market_eligibility.evidences.detect { |e| e.key.to_sym == :social_security_number_evidence }

          expect(ssn_evidence.current_state).to eq(:verified)
          expect(ssn_evidence.verification_outstanding).to eq false
          expect(ssn_evidence.is_satisfied).to eq true
          expect(ssn_evidence.due_on).to be_nil
        end
      end

      context 'when evidence current_state is failed' do
        let(:ssn_eligibility_hash) do
          {key: "individual_market_eligibility",
           evidences: [{key: "social_security_number_evidence",
                        request_results: [rr], current_state: :failed}]}
        end
        let(:params) do
          {call_type: 'application_determination', job_id: job.job_id, application_hbx_id: @application_hash[:hbx_id],
           response: @application_hash.to_json, app_type: 'faa',
           determinations: {ssa: @determinations, vlp: @determinations}}
        end

        before do
          @application_hash[:applicants].each do |applicant|
            applicant[:eligibilities] = [ssn_eligibility_hash]
          end
        end

        context 'when applicant is not enrolled' do
          it 'moves evidence to negative response received state' do
            subject.call(params)
            application.reload
            applicant = application.applicants.first
            individual_market_eligibility = applicant.individual_market_eligibility
            ssn_evidence = individual_market_eligibility.evidences.detect { |e| e.key.to_sym == :social_security_number_evidence }

            expect(ssn_evidence.current_state).to eq(:negative_response_received)
            expect(ssn_evidence.verification_outstanding).to eq false
            expect(ssn_evidence.is_satisfied).to eq true
            expect(ssn_evidence.due_on).to be_nil
          end
        end

        context 'when applicant is enrolled' do
          before do
            FactoryBot.create(:hbx_enrollment,
                              family: family,
                              aasm_state: 'coverage_selected',
                              household: family.active_household,
                              hbx_enrollment_members: [FactoryBot.build(:hbx_enrollment_member, applicant_id: applicant.family_member_id)])
          end

          it 'moves evidence to outstanding state with due date' do
            subject.call(params)
            application.reload
            applicant = application.applicants.first
            individual_market_eligibility = applicant.individual_market_eligibility
            ssn_evidence = individual_market_eligibility.evidences.detect { |e| e.key.to_sym == :social_security_number_evidence }

            expect(ssn_evidence.current_state).to eq(:outstanding)
            expect(ssn_evidence.verification_outstanding).to eq true
            expect(ssn_evidence.is_satisfied).to eq false
            expect(ssn_evidence.due_on).to be_present
          end
        end
      end

      context 'when evidence current_state is other states (outstanding, pending, etc.)' do
        let(:ssn_eligibility_hash) do
          {key: "individual_market_eligibility",
           evidences: [{key: "social_security_number_evidence",
                        request_results: [rr], current_state: :outstanding}]}
        end
        let(:params) do
          {call_type: 'application_determination', job_id: job.job_id, application_hbx_id: @application_hash[:hbx_id],
           response: @application_hash.to_json, app_type: 'faa',
           determinations: {ssa: @determinations, vlp: @determinations}}
        end

        before do
          @application_hash[:applicants].each do |applicant|
            applicant[:eligibilities] = [ssn_eligibility_hash]
          end
        end

        context 'when applicant is not enrolled' do
          it 'moves evidence to negative response received state' do
            subject.call(params)
            application.reload
            applicant = application.applicants.first
            individual_market_eligibility = applicant.individual_market_eligibility
            ssn_evidence = individual_market_eligibility.evidences.detect { |e| e.key.to_sym == :social_security_number_evidence }

            expect(ssn_evidence.current_state).to eq(:negative_response_received)
            expect(ssn_evidence.verification_outstanding).to eq false
            expect(ssn_evidence.is_satisfied).to eq true
            expect(ssn_evidence.due_on).to be_nil
          end
        end

        context 'when applicant is enrolled' do
          before do
            FactoryBot.create(:hbx_enrollment,
                              family: family,
                              aasm_state: 'coverage_selected',
                              household: family.active_household,
                              hbx_enrollment_members: [FactoryBot.build(:hbx_enrollment_member, applicant_id: applicant.family_member_id)])
          end

          it 'moves evidence to outstanding state with due date' do
            subject.call(params)
            application.reload
            applicant = application.applicants.first
            individual_market_eligibility = applicant.individual_market_eligibility
            ssn_evidence = individual_market_eligibility.evidences.detect { |e| e.key.to_sym == :social_security_number_evidence }

            expect(ssn_evidence.current_state).to eq(:outstanding)
            expect(ssn_evidence.verification_outstanding).to eq true
            expect(ssn_evidence.is_satisfied).to eq false
            expect(ssn_evidence.due_on).to be_present
          end
        end
      end
    end

    context 'with invalid job_id' do
      it 'returns failure when job not found' do
        result = subject.call({call_type: 'application_determination', job_id: 'invalid_job_id', application_hbx_id: @application_hash[:hbx_id],
                               response: @application_hash.to_json, app_type: 'faa',
                               determinations: {ssa: @determinations, vlp: @determinations}})
        expect(result).to be_failure
      end
    end

    context 'with invalid application_hbx_id' do
      it 'returns failure when application not found' do
        result = subject.call({call_type: 'application_determination', job_id: job.job_id, application_hbx_id: 'invalid_hbx_id',
                               response: @application_hash.to_json, app_type: 'faa',
                               determinations: {ssa: @determinations, vlp: @determinations}})
        expect(result).to be_failure
        expect(result.failure).to include("Application not found")
      end
    end

    context 'with invalid response payload' do
      before do
        @application_hash[:applicants].each do |applicant|
          applicant[:eligibilities] = [eligibility_hash]
        end
        @result = subject.call({call_type: 'application_determination', job_id: job.job_id, application_hbx_id: @application_hash[:hbx_id],
                                response: "invalid json", app_type: 'faa',
                                determinations: {ssa: @determinations, vlp: @determinations}})

      end
      it 'returns failure with malformed JSON' do
        expect(@result).to be_failure
      end

      it 'Transmittable objects are updated to failed state' do
        expect(::Transmittable::Job.first.process_status.latest_state).to eq(:failed)
        expect(::Transmittable::Transmission.first.process_status.latest_state).to eq(:failed)
        expect(::Transmittable::Transaction.first.process_status.latest_state).to eq(:failed)
      end

      it 'returns failure when payload validation fails' do
        @application_hash[:applicants].each do |applicant|
          applicant[:eligibilities] = [eligibility_hash]
        end
        invalid_payload = {"applicants" => []}.to_json
        result = subject.call({call_type: 'application_determination', job_id: job.job_id, application_hbx_id: @application_hash[:hbx_id],
                               response: invalid_payload,
                               determinations: {ssa: @determinations, vlp: @determinations}})
        expect(result).to be_failure
      end
    end

    context 'with missing parameters' do
      it 'returns failure when job_id is missing' do
        @application_hash[:applicants].each do |applicant|
          applicant[:eligibilities] = [eligibility_hash]
        end
        result = subject.call({call_type: 'application_determination', application_hbx_id: @application_hash[:hbx_id], response: @application_hash.to_json})
        expect(result).to be_failure
        expect(result.failure).to eq("Missing job_id")
      end

      it 'returns failure when application_hbx_id is missing' do
        @application_hash[:applicants].each do |applicant|
          applicant[:eligibilities] = [eligibility_hash]
        end
        result = subject.call({call_type: 'application_determination', job_id: job.job_id, response: @application_hash.to_json})
        expect(result).to be_failure
        expect(result.failure).to eq("Missing application_hbx_id")
      end

      it 'returns failure when response is missing or empty' do
        result = subject.call({call_type: 'application_determination', job_id: job.job_id, application_hbx_id: @application_hash[:hbx_id], response: ""})
        expect(result).to be_failure
        expect(result.failure).to eq("Response cannot be empty")
      end
    end
  end

  describe 'private methods' do
    describe '#validate_params' do
      it 'validates presence of required parameters' do
        result = subject.send(:validate_params, {
                                job_id: job.job_id,
                                application_hbx_id: 'app-123',
                                app_type: 'faa',
                                response: '{}',
                                determinations: {ssa: @determinations, vlp: @determinations},
                                call_type: 'application_determination'
                              })
        expect(result).to be_success
      end
    end

    describe '#find_matching_applicant' do
      context 'faa application' do
        let(:res_applicant_entity) do
          OpenStruct.new(
            person_hbx_id: application.applicants.first.person_hbx_id,
            person_name: OpenStruct.new(
              family_name: 'Smith',
              given_name: 'John'
            ),
            demographics: OpenStruct.new(
              dob: Date.new(1980, 1, 1)
            )
          )
        end

        before do
          subject.instance_variable_set(:@application, application)
        end

        it 'finds matching applicant for FAA application' do
          matching_applicant = subject.send(:find_matching_applicant, res_applicant_entity)
          expect(matching_applicant).not_to be_nil
          expect(matching_applicant.person_hbx_id).to eq(res_applicant_entity.person_hbx_id)
        end
      end

      context 'uqhp application' do
        let(:res_applicant_entity) do
          OpenStruct.new(
            person_name: OpenStruct.new(
              family_name: 'Doe',
              given_name: 'Johnny'
            ),
            demographics: OpenStruct.new(
              dob: Date.current - 25.years
            )
          )
        end

        before do
          uqhp_application = FactoryBot.create(:individual_market_application, :with_primary)
          subject.instance_variable_set(:@application, uqhp_application)
        end

        it 'finds matching applicant for uqhp application' do
          matching_applicant = subject.send(:find_matching_applicant, res_applicant_entity)
          expect(matching_applicant).not_to be_nil
        end
      end
    end
  end
end