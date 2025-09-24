# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::AptcCsrEligibility, type: :model do
  let(:applicant)   { FactoryBot.create(:individual_market_applicant, :dependent) }
  let(:eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }

  describe 'inheritance' do
    it 'inherits from Eligibilities::V3::Eligibility' do
      expect(described_class.superclass).to eq(Eligibilities::V3::Eligibility)
    end
  end

  describe 'associations' do
    it { should embed_many(:state_histories) }
    it { should embed_many(:determinations) }
    it { should embed_many(:evidences) }
  end

  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_uniqueness_of(:key) }
  end

  describe 'default values' do
    it 'sets current_state to initial by default' do
      expect(eligibility.current_state).to eq(:initial)
    end

    it 'sets is_satisfied to false by default' do
      expect(eligibility.is_satisfied).to be false
    end

    it 'sets is_disqualified to false by default' do
      expect(eligibility.is_disqualified).to be false
    end
  end

  describe '#unique_evidences validation' do
    context 'when there are duplicate evidence types' do
      before do
        evidence_type = 'Eligibilities::V3::Evidence::SocialSecurityNumber'
        2.times do
          evidence = FactoryBot.build(:v3_evidence, _type: evidence_type)
          eligibility.evidences << evidence
        end
      end

      it 'is invalid' do
        expect(eligibility).not_to be_valid
        expect(eligibility.errors[:evidences]).to include('cannot have duplicate evidence types')
      end
    end

    context 'when there are no duplicate evidence types' do
      before do
        eligibility.evidences << FactoryBot.build(:v3_evidence, _type: 'Eligibilities::V3::Evidence::SocialSecurityNumber')
        eligibility.evidences << FactoryBot.build(:v3_evidence, _type: 'Eligibilities::V3::Evidence::CitizenshipStatus')
      end

      it 'is valid' do
        expect(eligibility).to be_valid
      end
    end
  end

  describe 'state histories' do
    it 'can track state transitions' do
      state_history = FactoryBot.build(:v3_state_history, from_state: :initial, to_state: :eligible)
      eligibility.state_histories << state_history

      expect(eligibility.state_histories.count).to eq(1)
      expect(eligibility.state_histories.first.from_state).to eq(:initial)
      expect(eligibility.state_histories.first.to_state).to eq(:eligible)
    end

    it 'can have multiple state transitions' do
      eligibility.state_histories << FactoryBot.build(:v3_state_history, from_state: :initial, to_state: :pending)
      eligibility.state_histories << FactoryBot.build(:v3_state_history, from_state: :pending, to_state: :eligible)

      expect(eligibility.state_histories.count).to eq(2)
      expect(eligibility.state_histories.last.to_state).to eq(:eligible)
    end
  end

  describe 'evidence management' do
    it 'can have multiple evidences' do
      eligibility.evidences << FactoryBot.build(:v3_evidence, key: :citizenship)
      eligibility.evidences << FactoryBot.build(:v3_evidence, key: :income)

      expect(eligibility.evidences.count).to eq(2)
      expect(eligibility.evidences.map(&:key)).to contain_exactly('citizenship', 'income')
    end
  end

  describe '#evidence setup' do
    let(:determined_family) { FactoryBot.create(:family, :with_primary_family_member)}

    let(:determined_application) do
      FactoryBot.create(:financial_assistance_application, aasm_state: "determined", family_id: determined_family.id)
    end

    let(:ed) do
      eli_d = FactoryBot.create(:financial_assistance_eligibility_determination, application: determined_application)
      eli_d.update_attributes!(hbx_assigned_id: '12345')
      eli_d
    end

    let(:determined_applicant) do
      FactoryBot.create(:financial_assistance_applicant,
                        :with_income_evidence,
                        eligibility_determination_id: ed.id,
                        person_hbx_id: '1629165429385938',
                        is_primary_applicant: true,
                        first_name: 'Income',
                        last_name: 'evidence',
                        ssn: "111111111",
                        dob: Date.new(1988, 11, 11),
                        family_member_id: determined_family.primary_family_member.id,
                        application: determined_application)
    end

    let(:setup_data) do
      create_embed_docs
      ed
      update_benchmark_premiums(determined_application)
      determined_application.save!
    end

    let(:aptc_eligibility)  do
      aptc_csr_eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: determined_applicant)
      old_state = FactoryBot.build(:v3_state_history, created_at: 2.days.ago)
      new_state = FactoryBot.build(:v3_state_history, created_at: 1.day.ago)
      aptc_csr_eligibility.state_histories << old_state
      aptc_csr_eligibility.state_histories << new_state
      aptc_csr_eligibility.save!
      aptc_csr_eligibility
    end

    let(:income_evidence) do
      FactoryBot.create(:income_evidence, eligibility: aptc_eligibility, _type: 'FinancialAssistance::Evidences::IncomeEvidence',key: :income_evidence, title: 'Income Evidence', determined_at: TimeKeeper.date_of_record,
                                          description: 'Income Evidence Description', current_state: income_evidence_state)
    end

    let(:esi_evidence) do
      FactoryBot.create(:income_evidence, eligibility: aptc_eligibility, _type: 'FinancialAssistance::Evidences::EsiMecEvidence',key: :esi_mec_evidence, title: 'Esi MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                          description: 'EsiMecEvidence', current_state: esi_evidence_state)
    end

    let(:non_esi_evidence) do
      FactoryBot.create(:income_evidence, eligibility: aptc_eligibility, _type: 'FinancialAssistance::Evidences::NonEsiMecEvidence',key: :non_esi_mec_evidence, title: 'Non Esi MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                          description: 'NonEsiMecEvidence', current_state: non_esi_evidence_state)
    end

    let(:local_mec_evidence) do
      FactoryBot.create(:income_evidence, eligibility: aptc_eligibility, _type: 'FinancialAssistance::Evidences::LocalMecEvidence',key: :local_mec_evidence, title: 'Local MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                          description: 'LocalMecEvidence', current_state: local_mec_evidence_state)
    end

    let(:create_embed_docs) do
      [income_evidence, esi_evidence, non_esi_evidence].each do |evidence|
        FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 2.days.ago)
        FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 1.day.ago)
        FactoryBot.create(:v3_verification_history, evidence: evidence)
        evidence.documents.create(title: 'document.pdf', creator: 'mehl', subject: 'document.pdf', publisher: 'mehl', type: 'text', identifier: 'identifier', source: 'enroll_system', language: 'en')
      end
    end

    describe "#determine_eligibility_state" do
      context 'when all evidences are verified' do
        let(:income_evidence_state) {:pending}
        let(:esi_evidence_state) {:pending}
        let(:non_esi_evidence_state) {:pending}
        let(:local_mec_evidence_state) {:pending}

        before do
          income_evidence.mark_as_verified
          esi_evidence.mark_as_verified
          non_esi_evidence.mark_as_verified
          local_mec_evidence.mark_as_verified
        end

        it 'sets eligibility to satisfied' do
          aptc_eligibility.determine_eligibility_state('All evidences verified')
          expect(aptc_eligibility.is_satisfied).to be true
          expect(aptc_eligibility.current_state).to eq(:satisfied)
        end
      end

      context 'when some evidences are pending' do
        let(:income_evidence_state) {:pending}
        let(:esi_evidence_state) {:pending}
        let(:non_esi_evidence_state) {:pending}
        let(:local_mec_evidence_state) {:pending}

        before do
          income_evidence.mark_as_verified
          esi_evidence.mark_as_verified
          non_esi_evidence.mark_as_verified
          local_mec_evidence
        end

        it 'sets eligibility to pending' do
          aptc_eligibility.determine_eligibility_state('Some evidences pending')
          expect(aptc_eligibility.is_satisfied).to be false
          expect(aptc_eligibility.current_state).to eq(:verification_in_progress)
        end
      end
    end

    context '#update_evidences_for_enrollment_change' do
      let(:income_evidence_state) {:pending}
      let(:esi_evidence_state) {:outstanding}
      let(:non_esi_evidence_state) {:negative_response_received}
      let(:local_mec_evidence_state) {:verified}
      before do
        income_evidence
        esi_evidence
        non_esi_evidence
        local_mec_evidence
        aptc_eligibility.update_evidences_for_enrollment_change
      end

      it 'should update income evidence to outstanding' do
        expect(income_evidence.current_state).to eq(:outstanding)
      end

      it 'should not update esi evidence' do
        expect(esi_evidence.current_state).to eq(:outstanding)
      end

      it 'should update non esi evidence' do
        expect(non_esi_evidence.current_state).to eq(:outstanding)
      end

      it 'should not update local mec evidence' do
        expect(local_mec_evidence.current_state).to eq(:verified)
      end
    end

    context '#update_outstanding_evidences_for_non_enrolled' do
      let(:income_evidence_state) {:pending}
      let(:esi_evidence_state) {:outstanding}
      let(:non_esi_evidence_state) {:negative_response_received}
      let(:local_mec_evidence_state) {:verified}
      before do
        income_evidence
        esi_evidence
        non_esi_evidence
        local_mec_evidence
        aptc_eligibility.update_outstanding_evidences_for_non_enrolled
      end

      it 'should update income evidence to outstanding' do
        expect(income_evidence.current_state).to eq(:pending)
      end

      it 'should not update esi evidence' do
        expect(esi_evidence.current_state).to eq(:negative_response_received)
      end

      it 'should update non esi evidence' do
        expect(non_esi_evidence.current_state).to eq(:negative_response_received)
      end

      it 'should not update local mec evidence' do
        expect(local_mec_evidence.current_state).to eq(:verified)
      end
    end
  end
end

def update_benchmark_premiums(determined_application)
  applicant_hbx_ids = determined_application.applicants.pluck(:person_hbx_id)
  member_premiums = applicant_hbx_ids.collect do |applicant_hbx_id|
    { member_identifier: applicant_hbx_id, monthly_premium: 90.0 }
  end.compact
  premiums_info = { health_only_lcsp_premiums: member_premiums, health_only_slcsp_premiums: member_premiums }
  determined_application.applicants.each { |applicant| applicant.benchmark_premiums = premiums_info }
  determined_application.save!
  determined_application.reload
end
