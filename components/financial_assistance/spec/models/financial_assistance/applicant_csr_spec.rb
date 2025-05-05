# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::FinancialAssistance::Applicant, type: :model do

  let(:application) do
    FactoryBot.create(:financial_assistance_application,
                      family_id: BSON::ObjectId.new,
                      aasm_state: 'draft',
                      assistance_year: TimeKeeper.date_of_record.year,
                      effective_date: Date.today)
  end

  let(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      application: application,
                      dob: Date.today - 40.years,
                      is_ia_eligible: aptc_eligible,
                      is_csr_eligible: csr_eligible,
                      csr_percent_as_integer: csr,
                      csr_eligibility_kind: csr_kind,
                      is_primary_applicant: true,
                      family_member_id: BSON::ObjectId.new)
  end

  before do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(enabled)
  end

  describe '#is_csr_73_87_or_94?' do
    let(:csr) { 94 }
    let(:csr_kind) { 'csr_94' }

    context 'when qhp_application_feature is enabled' do
      let(:enabled) { true }

      context 'when:
        - aptc_eligible is false
        - csr_eligible is true' do

        let(:aptc_eligible) { false }
        let(:csr_eligible) { true }

        it 'returns true' do
          expect(applicant.is_csr_73_87_or_94?).to be_truthy
        end
      end

      context 'when:
        - aptc_eligible is false
        - csr_eligible is false' do
        let(:aptc_eligible) { false }
        let(:csr_eligible) { false }

        it 'returns false' do
          expect(applicant.is_csr_73_87_or_94?).to be_falsey
        end
      end
    end

    context 'when qhp_application_feature is disabled' do
      let(:enabled) { false }

      context 'when:
        - aptc_eligible is false
        - csr_eligible is true' do

        let(:aptc_eligible) { false }
        let(:csr_eligible) { true }

        it 'returns false' do
          expect(applicant.is_csr_73_87_or_94?).to be_falsey
        end
      end

      context 'when:
        - aptc_eligible is true
        - csr_eligible is true' do

        let(:aptc_eligible) { true }
        let(:csr_eligible) { true }

        it 'returns true' do
          expect(applicant.is_csr_73_87_or_94?).to be_truthy
        end
      end
    end
  end

  describe '#is_csr_100?' do
    let(:csr) { 100 }
    let(:csr_kind) { 'csr_100' }

    context 'when qhp_application_feature is enabled' do
      let(:enabled) { true }

      context 'when:
        - aptc_eligible is false
        - csr_eligible is true' do

        let(:aptc_eligible) { false }
        let(:csr_eligible) { true }

        it 'returns true' do
          expect(applicant.is_csr_100?).to be_truthy
        end
      end

      context 'when:
        - aptc_eligible is false
        - csr_eligible is false' do
        let(:aptc_eligible) { false }
        let(:csr_eligible) { false }

        it 'returns false' do
          expect(applicant.is_csr_100?).to be_falsey
        end
      end
    end

    context 'when qhp_application_feature is disabled' do
      let(:enabled) { false }

      context 'when:
        - aptc_eligible is false
        - csr_eligible is true' do

        let(:aptc_eligible) { false }
        let(:csr_eligible) { true }

        it 'returns false' do
          expect(applicant.is_csr_100?).to be_falsey
        end
      end

      context 'when:
        - aptc_eligible is true
        - csr_eligible is true' do

        let(:aptc_eligible) { true }
        let(:csr_eligible) { true }

        it 'returns true' do
          expect(applicant.is_csr_100?).to be_truthy
        end
      end
    end
  end

  describe '#is_csr_limited?' do
    let(:csr) { -1 }
    let(:csr_kind) { 'csr_limited' }

    context 'when qhp_application_feature is enabled' do
      let(:enabled) { true }

      context 'when:
        - aptc_eligible is false
        - csr_eligible is true' do

        let(:aptc_eligible) { false }
        let(:csr_eligible) { true }

        it 'returns true' do
          expect(applicant.is_csr_limited?).to be_truthy
        end
      end

      context 'when:
        - aptc_eligible is false
        - csr_eligible is false' do
        let(:aptc_eligible) { false }
        let(:csr_eligible) { false }

        it 'returns false' do
          expect(applicant.is_csr_limited?).to be_falsey
        end
      end
    end

    context 'when qhp_application_feature is disabled' do
      let(:enabled) { false }

      context 'when:
        - aptc_eligible is false
        - csr_eligible is true' do

        let(:aptc_eligible) { false }
        let(:csr_eligible) { true }

        it 'returns false' do
          expect(applicant.is_csr_limited?).to be_falsey
        end
      end

      context 'when:
        - aptc_eligible is true
        - csr_eligible is true' do

        let(:aptc_eligible) { true }
        let(:csr_eligible) { true }

        it 'returns true' do
          expect(applicant.is_csr_limited?).to be_truthy
        end
      end
    end
  end
end
