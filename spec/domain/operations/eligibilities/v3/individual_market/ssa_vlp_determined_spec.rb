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
  let(:eligibility_hash) do
    {:key => "individual_market_eligibility",
     :evidences => [{:key => "social_security_number_evidence",
                     :request_results => [rr],:current_state => :attested},
                    {:key => "citizenship_evidence", :request_results => [rr], :current_state => :outstanding},
                    {:key => "immigration_evidence", :request_results => [rr], :current_state => :outstanding}]}
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
      @application_hash[:applicants].each do |applicant|
        applicant[:eligibilities] = [eligibility_hash]
      end
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
        @result = subject.call({job_id: job.job_id, application_hbx_id: @application_hash[:hbx_id], response: @application_hash.to_json, app_type: 'faa'})
      end
      it 'returns success with message' do
        expect(@result).to be_success
        expect(::Transmittable::Job.first.process_status.latest_state).to eq(:succeeded)
        expect(::Transmittable::Transmission.first.process_status.latest_state).to eq(:succeeded)
        expect(::Transmittable::Transaction.first.process_status.latest_state).to eq(:succeeded)
      end

      it 'updates evidence states correctly' do
        application.reload
        applicant = application.applicants.first
        individual_market_eligibility = applicant.individual_market_eligibility

        ssn_evidence = individual_market_eligibility.evidences.detect { |e| e.key.to_sym == :social_security_number_evidence }
        citizenship_evidence = individual_market_eligibility.evidences.detect { |e| e.key.to_sym == :citizenship_evidence }
        immigration_evidence = individual_market_eligibility.evidences.detect { |e| e.key.to_sym == :immigration_evidence }

        expect(ssn_evidence.current_state).to eq(:verified)
        expect(citizenship_evidence.current_state).to eq(:negative_response_received)
        expect(immigration_evidence.current_state).to eq(:negative_response_received)
      end

      it 'creates request results for each evidence' do
        application.reload
        applicant = application.applicants.first
        individual_market_eligibility = applicant.individual_market_eligibility

        ssn_evidence = individual_market_eligibility.evidences.detect { |e| e.key.to_sym == :social_security_number_evidence }
        citizenship_evidence = individual_market_eligibility.evidences.detect { |e| e.key.to_sym == :citizenship_evidence }

        expect(ssn_evidence.request_results.count).to eq(1)
        expect(ssn_evidence.request_results.first.result).to eq('test_state')
        expect(ssn_evidence.request_results.first.source).to eq('FDSH SSA')
        expect(ssn_evidence.request_results.first.code).to eq('HS000000')

        expect(citizenship_evidence.request_results.count).to eq(1)
      end
    end

    context 'with invalid job_id' do
      it 'returns failure when job not found' do
        result = subject.call({job_id: 'invalid_job_id', application_hbx_id: @application_hash[:hbx_id], response: @application_hash.to_json, app_type: 'faa'})
        expect(result).to be_failure
      end
    end

    context 'with invalid application_hbx_id' do
      it 'returns failure when application not found' do
        result = subject.call({job_id: job.job_id, application_hbx_id: 'invalid_hbx_id', response: @application_hash.to_json, app_type: 'faa'})
        expect(result).to be_failure
        expect(result.failure).to include("Application not found")
      end
    end

    context 'with invalid response payload' do
      before do
        @result = subject.call({job_id: job.job_id, application_hbx_id: @application_hash[:hbx_id], response: "invalid json", app_type: 'faa'})

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
        invalid_payload = {"applicants" => []}.to_json
        result = subject.call({job_id: job.job_id, application_hbx_id: @application_hash[:hbx_id], response: invalid_payload})
        expect(result).to be_failure
      end
    end

    context 'with missing parameters' do
      it 'returns failure when job_id is missing' do
        result = subject.call({application_hbx_id: @application_hash[:hbx_id], response: @application_hash.to_json})
        expect(result).to be_failure
        expect(result.failure).to eq("Missing job_id")
      end

      it 'returns failure when application_hbx_id is missing' do
        result = subject.call({job_id: job.job_id, response: @application_hash.to_json})
        expect(result).to be_failure
        expect(result.failure).to eq("Missing application_hbx_id")
      end

      it 'returns failure when response is missing or empty' do
        result = subject.call({job_id: job.job_id, application_hbx_id: @application_hash[:hbx_id], response: ""})
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
                                response: '{}'
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