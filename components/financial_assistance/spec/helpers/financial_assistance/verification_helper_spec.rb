# frozen_string_literal: true

require 'rails_helper'
RSpec.describe ::FinancialAssistance::VerificationHelper, :type => :helper, dbclean: :after_each do
  let!(:application) { FactoryBot.create(:financial_assistance_application, family_id: BSON::ObjectId.new) }
  let!(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      application: application,
                      is_claimed_as_tax_dependent: false,
                      is_required_to_file_taxes: true,
                      first_name: 'Test',
                      last_name: 'Test10')
  end

  let!(:evidence) do
    applicant.create_income_evidence(key: :income,
                                     title: 'Income',
                                     aasm_state: 'pending',
                                     due_on: Date.today,
                                     verification_outstanding: true,
                                     is_satisfied: false)
  end

  context 'applicant applying for coverage' do
    it 'should return true as evidence is unverified' do
      expect(helper.display_upload_for_evidence?(evidence)).to eq true
    end
  end

  context 'applicant not applying for coverage' do
    it 'should return true as evidence is unverified' do
      applicant.is_applying_coverage = false
      applicant.save!
      expect(helper.display_upload_for_evidence?(evidence)).to eq true
    end
  end

  context 'with evidence in different states' do
    shared_examples_for 'evidence upload requirements' do |state, expected_result|
      let(:evidence) do
        applicant.create_income_evidence(
          key: :income,
          title: 'Income',
          aasm_state: state,
          is_satisfied: state == 'verified',
          verification_outstanding: state == 'outstanding'
        )
      end

      before do
        allow(evidence).to receive(:no_document_upload_required?).and_return(!expected_result)
      end

      it "returns #{expected_result} for #{state} evidence" do
        expect(helper.display_upload_for_evidence?(evidence)).to eq expected_result
      end
    end

    it_behaves_like 'evidence upload requirements', 'outstanding', true
    it_behaves_like 'evidence upload requirements', 'verified', false
    it_behaves_like 'evidence upload requirements', 'pending', true
    it_behaves_like 'evidence upload requirements', 'rejected', true
    it_behaves_like 'evidence upload requirements', 'negative_response_received', false
  end
end
