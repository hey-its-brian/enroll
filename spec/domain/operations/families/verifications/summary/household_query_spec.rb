# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Families::Verifications::Summary::HouseholdQuery, dbclean: :after_each do
  subject { described_class.new }

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }

  before :all do
    ENV['ENABLE_ALIVE_STATUS'] = 'true'
    ENV['LOCAL_MEC_EVIDENCE_IS_ENABLED'] = 'true'
    ENV['QHP_APPLICATION_IS_ENABLED'] = 'true'
    load Rails.root.join('config', 'initializers', 'enroll_registry.rb')
  end

  after :all do
    ENV['ENABLE_ALIVE_STATUS'] = nil
    ENV['LOCAL_MEC_EVIDENCE_IS_ENABLED'] = nil
    ENV['QHP_APPLICATION_IS_ENABLED'] = nil
    load Rails.root.join('config', 'initializers', 'enroll_registry.rb')
  end

  context 'parameter validation' do
    it 'returns an error when family is not provided' do
      result = subject.call({})
      expect(result.failure?).to be true
      expect(result.failure).to eq('Family is missing')
    end
  end

  context 'family without determination' do
    it 'returns an error when family has no eligible applications' do
      result = subject.call(family: family)
      expect(result.failure?).to be true
      expect(result.failure).to eq(:no_eligible_applications)
    end
  end

  context 'family with valid determination' do
    let(:faa_application) do
      FactoryBot.create(
        :financial_assistance_application,
        family_id: family.id,
        aasm_state: 'determined',
        submitted_at: Time.now,
        assistance_year: TimeKeeper.date_of_record.year
      )
    end

    let(:applicant) do
      FactoryBot.create(
        :financial_assistance_applicant,
        family_member_id: primary_applicant.id,
        person_hbx_id: person.hbx_id,
        application: faa_application
      )
    end

    let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
    let(:alive_evidence) { FactoryBot.create(:alive_evidence, :pending, eligibility: ivl_eligibility) }
    let(:ai_an_evidence) { FactoryBot.create(:american_indian_evidence, :with_verification_histories, :verified, eligibility: ivl_eligibility) }
    let(:citizenship_evidence) { FactoryBot.create(:citizenship_evidence, :with_verification_histories, :rejected, eligibility: ivl_eligibility) }
    let(:ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: ivl_eligibility) }

    let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
    let(:esi_evidence) { FactoryBot.create(:esi_mec_evidence, :with_verification_histories, :pending, eligibility: aptc_csr_eligibility) }
    let(:income_evidence) { FactoryBot.create(:income_evidence, :with_verification_histories, :verified, eligibility: aptc_csr_eligibility) }
    let(:local_evidence) { FactoryBot.create(:local_mec_evidence, :with_verification_histories, :rejected, eligibility: aptc_csr_eligibility) }
    let(:non_esi_evidence) { FactoryBot.create(:non_esi_mec_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility) }

    before do
      esi_evidence
      income_evidence
      local_evidence
      non_esi_evidence
      alive_evidence
      ai_an_evidence
      citizenship_evidence
      ssn_evidence

      family.assign_latest_application_gid
      family.save!
    end

    it 'returns successfully with appropriate action items and subjects' do
      result = subject.call(family: family, person_id: person.id)

      expect(result.success?).to be true

      action_items = result.success[:action_items]
      expect(action_items).to be_present
      expect(action_items.map(&:evidence_item_key)).to include(:non_esi_evidence, :social_security_number, :local_mec_evidence, :citizenship)
      expect(action_items.map(&:evidence_item_key)).not_to include(:income_evidence, :american_indian)

      expect(action_items).to eq(action_items.sort_by { |item| item.due_on || Float::INFINITY })

      subjects = result.success[:subjects]
      expect(subjects).to be_present
      expect(subjects).to eq(subjects.sort_by { |subject| [subject.cumulative_grouped_status.to_s, subject.earliest_due_date || Float::INFINITY] })
    end

    context 'with inactive members' do
      let!(:inactive_dependent) do
        dependent_member = FactoryBot.build(:family_member, family: family, is_primary_applicant: false, person: FactoryBot.create(:person, first_name: "Child"))
        family.dependents.each do |dependent|
          family.relate_new_member(dependent.person, "child")
        end
        dependent_member.is_active = false
        family.save
      end

      it 'excludes inactive members by default' do
        result = subject.call(family: family, include_inactives: true)

        expect(result.success?).to be true
        expect(result.success[:subjects].map(&:is_active?)).to all(be true)
      end

      it 'includes inactive members when flag and feature are enabled' do
        EnrollRegistry[:show_inactive_verification_members].feature.stub(:is_enabled).and_return(true)

        result = subject.call(family: family, include_inactives: true)

        expect(result.success?).to be true
        expect(result.success[:subjects].map(&:is_active?)).to include(false)
      end
    end
  end
end
