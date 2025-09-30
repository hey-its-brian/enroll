# frozen_string_literal: true

require 'rails_helper'
require "#{FinancialAssistance::Engine.root}/spec/shared_examples/ifsv/test_ifsv_eligibility_response"

RSpec.describe ::FinancialAssistance::Operations::Applications::Rrv::IncomeEvidence::DetermineAndStoreResponse, dbclean: :after_each do
  include_context 'FDSH IFSV sample response'

  before :all do
    DatabaseCleaner.clean
  end

  let(:family) do
    FactoryBot.create(:family, :with_primary_family_member, person: FactoryBot.create(:person))
  end

  let!(:application) do
    FactoryBot.create(:financial_assistance_application, family_id: family.id, hbx_id: '200000126', aasm_state: "determined")
  end

  let!(:ed) do
    eli_d = FactoryBot.create(:financial_assistance_eligibility_determination, application: application)
    eli_d.update_attributes!(hbx_assigned_id: '12345')
    eli_d
  end

  let!(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      :with_income_evidence,
                      eligibility_determination_id: ed.id,
                      family_member_id: family.family_members.first.id,
                      person_hbx_id: '1629165429385938',
                      is_primary_applicant: true,
                      is_ia_eligible: true,
                      first_name: 'Income',
                      last_name: 'evidence',
                      ssn: "111111111",
                      dob: Date.new(1988, 11, 11),
                      application: application)
  end

  let!(:applicant2) do
    FactoryBot.create(:financial_assistance_applicant,
                      eligibility_determination_id: ed.id,
                      person_hbx_id: '1629165429385939',
                      is_primary_applicant: true,
                      first_name: 'Non Income',
                      last_name: 'evidence',
                      ssn: "222222222",
                      dob: Date.new(1989, 11, 11),
                      application: application)
  end

  before do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:ifsv_determination).and_return(true)
  end

  context 'success' do
    before do
      @applicant = application.applicants.first
      @applicant.build_aptc_eligibilities_evidences
      @applicant.save!
    end

    context 'FDSH RRV Ifsv eligible response' do

      before do
        @applicant&.aptc_csr_eligibility&.local_mec_evidence&.update!(current_state: :verified)
        @applicant&.aptc_csr_eligibility&.esi_mec_evidence&.update!(current_state: :verified)
        @applicant&.aptc_csr_eligibility&.non_esi_mec_evidence&.update!(current_state: :verified)
        @result = subject.call(payload: response_payload)
        @application = ::FinancialAssistance::Application.by_hbx_id(response_payload[:hbx_id]).first.reload
        @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(response_payload).success
        @applicant.reload

        @income_evidence = @applicant&.aptc_csr_eligibility&.income_evidence
      end

      it 'should return success' do
        expect(@result).to be_success
      end

      it 'should update applicant verification' do
        expect(@income_evidence.current_state).to eq :verified
        expect(@income_evidence.request_results.present?).to eq true
        expect(@result.success).to eq('Successfully updated Applicant with evidence')
      end

      it "should record request results" do
        expect(@income_evidence.request_results.first.action).to eq "RRV Response"
      end

      it "should update the aptc_csr_eligibility is_satisfied to true" do
        expect(@income_evidence.eligibility.is_satisfied).to eq true
      end

      context "applicant without evidence" do
        it 'should log an error if no income evidence present for an applicant' do
          person_hbx_id = application.applicants.last.person_hbx_id
          log_message = "Income Evidence not found for applicant with person_hbx_id: #{person_hbx_id} in application with hbx_id: #{application.hbx_id}"
          expect(Rails.logger).to receive(:error).at_least(:once).with(log_message)
          subject.call(payload: response_payload)
        end
      end
    end

    context 'FDSH RRV Ifsv ineligible response' do
      before do
        @result = subject.call(payload: response_payload_2)

        @application = ::FinancialAssistance::Application.by_hbx_id(response_payload_2[:hbx_id]).first.reload
        @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(response_payload_2).success
        @applicant.reload
        @income_evidence = @applicant&.aptc_csr_eligibility&.income_evidence
      end

      it 'should return success' do
        expect(@result).to be_success
      end

      it "should record request results" do
        expect(@income_evidence.request_results.first.action).to eq "RRV Response"
      end
    end

    context 'Avoid duplicate evidence update' do
      before do
        @applicant.income_evidence.request_results.create!(action: "RRV Response", created_at: 1.days.ago)
        @result = subject.call(payload: response_payload_2)

        @application = ::FinancialAssistance::Application.by_hbx_id(response_payload_2[:hbx_id]).first.reload
        @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(response_payload_2).success
        @applicant.reload
        @income_evidence = @applicant&.aptc_csr_eligibility&.income_evidence
      end

      it 'should return success' do
        expect(@result).to be_success
      end

      it "should not record request results" do
        expect(@income_evidence.request_results.count).to eq 1
      end
    end

    RSpec.shared_examples_for "enrollment with csr_variant_id" do |csr_variant_id, is_aptc_zero, expected_evidence_status|
      before :each do
        product = FactoryBot.create(:benefit_markets_products_health_products_health_product, csr_variant_id: csr_variant_id)
        FactoryBot.create(:hbx_enrollment, :with_enrollment_members, family: family, enrollment_members: family.family_members, product: product, applied_aptc_amount: is_aptc_zero ? 0.00 : 100.00)
        response_payload[:tax_households].first[:is_ifsv_eligible] = false
        allow_any_instance_of(FinancialAssistance::Applicant).to receive(:find_person).and_return(family.family_members.first.person)
        @result = subject.call(payload: response_payload)

        @application = ::FinancialAssistance::Application.by_hbx_id(response_payload[:hbx_id]).first.reload
        @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(response_payload).success
        @applicant.reload
        @income_evidence = @applicant&.aptc_csr_eligibility&.income_evidence
      end

      it 'should return success' do
        expect(@result).to be_success
      end

      it 'should set the aasm_state on local mec evidence to outstanding when csr is income based and has aptc' do
        expect(@income_evidence.current_state).to eq expected_evidence_status
      end
    end

    context 'ifsv_income_nrr flag' do
      context 'Negative Response Received logic update with flag on' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:ifsv_income_nrr).and_return(true)
        end

        it_behaves_like "enrollment with csr_variant_id", "01", false, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "01", true, :negative_response_received
        it_behaves_like "enrollment with csr_variant_id", "02", true, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "03", false, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "03", true, :negative_response_received
        it_behaves_like "enrollment with csr_variant_id", "04", true, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "05", true, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "06", true, :outstanding
      end

      context 'Negative Response Received logic update with flag off' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:ifsv_income_nrr).and_return(false)
        end

        it_behaves_like "enrollment with csr_variant_id", "01", false, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "01", true, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "02", true, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "03", false, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "03", true, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "04", true, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "05", true, :outstanding
        it_behaves_like "enrollment with csr_variant_id", "06", true, :outstanding
      end
    end
  end
end
