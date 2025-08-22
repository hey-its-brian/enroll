# frozen_string_literal: true

require 'rails_helper'
require "#{FinancialAssistance::Engine.root}/spec/shared_examples/rrv/medicare/test_rrv_medicare_response"

RSpec.describe ::FinancialAssistance::Operations::Applications::Rrv::NonEsiEvidence::DetermineAndStoreResponse, dbclean: :after_each do
  before :all do
    DatabaseCleaner.clean
  end

  let!(:family) { FactoryBot.create(:family, :with_primary_family_member)}
  let!(:application) do
    FactoryBot.create(:financial_assistance_application, hbx_id: '200000126', aasm_state: "determined", family_id: family.id)
  end

  let!(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      eligibility_determination_id: nil,
                      person_hbx_id: '1629165429385938',
                      is_primary_applicant: true,
                      first_name: 'esi',
                      last_name: 'evidence',
                      ssn: "518124854",
                      dob: Date.new(1988, 11, 11),
                      family_member_id: family.primary_family_member.id,
                      application: application)
  end

  context 'success' do
    context 'FDSH RRV Non ESI outstanding response when enrolled with aptc' do
      include_context 'FDSH RRV Medicare sample response'
      let!(:enrollment) { FactoryBot.create(:hbx_enrollment, :with_enrollment_members, :with_health_product, family: family, enrollment_members: family.family_members) }

      before do
        @applicant = application.applicants.first
        @applicant.build_aptc_eligibilities_evidences
        @applicant.save!
        @result = subject.call({payload: response_payload, applicant_identifier: '1629165429385938', call_type: 'hub_call'})

        @application = ::FinancialAssistance::Application.by_hbx_id(response_payload[:hbx_id]).first.reload
        @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(response_payload).success
        @applicant.reload
      end

      it 'should return success' do
        expect(@result).to be_success
      end

      it 'should update applicant verification' do
        expect(@applicant.aptc_csr_eligibility.non_esi_mec_evidence.current_state).to eq :negative_response_received
        expect(@result.success).to include('Application is saved for application with hbx_id')
      end

      it "should record request results" do
        expect(@applicant.aptc_csr_eligibility.non_esi_mec_evidence.request_results.first.action).to eq "Hub Response"
      end
    end

    context 'FDSH RRV Non ESI Medicare outstanding response when not enrolled' do
      include_context 'FDSH RRV Medicare sample response'

      before do
        @applicant = application.applicants.first
        @applicant.build_aptc_eligibilities_evidences
        @applicant.save!
        @result = subject.call({payload: response_payload, applicant_identifier: '1629165429385938', call_type: 'hub_call'})

        @application = ::FinancialAssistance::Application.by_hbx_id(response_payload[:hbx_id]).first.reload
        @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(response_payload).success
        @applicant.reload
      end

      it 'should return success' do
        expect(@result).to be_success
      end

      it 'should update applicant verification' do
        expect(@applicant&.aptc_csr_eligibility&.non_esi_mec_evidence&.current_state).to eq :negative_response_received
        expect(@result.success).to include('Application is saved for application with hbx_id')
      end

      it "should record request results" do
        expect(@applicant.aptc_csr_eligibility.non_esi_mec_evidence.request_results.first.action).to eq "Hub Response"
      end
    end

    context 'FDSH RRV Non ESI Medicare outstanding response when enrolled not assisted' do
      include_context 'FDSH RRV Medicare sample response'
      let(:enrollment) do
        FactoryBot.create(:hbx_enrollment, :with_enrollment_members, product: FactoryBot.create(:benefit_markets_products_health_products_health_product, csr_variant_id: '00'),
                                                                     family: family, enrollment_members: family.family_members, applied_aptc_amount: 0)
      end

      before do
        @applicant = application.applicants.first
        @applicant.build_aptc_eligibilities_evidences
        @applicant.save!
        @result = subject.call({payload: response_payload, applicant_identifier: '1629165429385938', call_type: 'hub_call'})

        @application = ::FinancialAssistance::Application.by_hbx_id(response_payload[:hbx_id]).first.reload
        @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(response_payload).success
        @applicant.reload
      end

      it 'should return success' do
        expect(@result).to be_success
      end

      it 'should update applicant verification' do
        expect(@applicant&.aptc_csr_eligibility&.non_esi_mec_evidence&.current_state).to eq :negative_response_received
        expect(@result.success).to include('Application is saved for application with hbx_id')
      end

      it "should record request results" do
        expect(@applicant.aptc_csr_eligibility.non_esi_mec_evidence.request_results.first.action).to eq "Hub Response"
      end
    end

    context 'FDSH RRV Non ESI Medicare attested response' do
      include_context 'FDSH RRV Medicare sample response'

      before do
        @applicant = application.applicants.first
        @applicant.build_aptc_eligibilities_evidences
        @applicant.save!
        @result = subject.call(payload: response_payload_2, applicant_identifier: '1629165429385938', call_type: 'hub_call')

        @application = ::FinancialAssistance::Application.by_hbx_id(response_payload[:hbx_id]).first.reload
        @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(response_payload).success
        @applicant.reload
      end

      it 'should return success' do
        expect(@result).to be_success
      end

      it 'should update applicant verification' do
        expect(@applicant&.aptc_csr_eligibility&.non_esi_mec_evidence&.current_state).to eq :attested
        expect(@result.success).to include('Application is saved for application with hbx_id')
      end

      it "should record request results" do
        expect(@applicant.aptc_csr_eligibility.non_esi_mec_evidence.request_results.first.action).to eq "Hub Response"
      end
    end

    context 'when applicant non-ESI evidence is not found' do
      include_context 'FDSH RRV Medicare sample response'

      before do
        @applicant = application.applicants.first
        # Don't build aptc_eligibilities_evidences to simulate missing non_esi_mec_evidence
        @applicant.save!
        @result = subject.call({payload: response_payload, applicant_identifier: '1629165429385938', call_type: 'hub_call'})
        @applicant.reload
      end

      it 'should return failure' do
        expect(@result).to be_failure
      end

      it 'should return failure message for missing evidence' do
        expect(@result.failure).to eq('Applicant non-ESI evidence not found')
      end

      it 'should not have non_esi_mec_evidence' do
        expect(@applicant&.aptc_csr_eligibility&.non_esi_mec_evidence).to be_nil
      end
    end
  end
end
