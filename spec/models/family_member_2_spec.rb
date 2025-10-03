# frozen_string_literal: true

require 'rails_helper'

describe FamilyMember do
  describe '#notify_family' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person, crm_notifiction_needed: false) }
    let(:primary_member) { family.primary_applicant }

    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:async_publish_updated_families).and_return(enabled_or_disabled)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:check_for_crm_updates).and_return(true)
      primary_member.send(:notify_family)
    end

    context 'enabled' do
      let(:enabled_or_disabled) { true }

      it 'does not set crm_notifiction_needed' do
        expect(family.crm_notifiction_needed).to be_falsey
      end
    end

    context 'disabled' do
      let(:enabled_or_disabled) { false }

      it 'sets crm_notifiction_needed' do
        expect(family.crm_notifiction_needed).to be_truthy
      end
    end
  end

  describe 'find_latest_determined_application_with_evidence_key' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:primary_member) { family.primary_applicant }
    let(:subject) { FactoryBot.build(:family_member, person: person, family: family) }
    let(:ivl_application) { FactoryBot.create(:individual_market_application, :determined, family: family) }
    let(:ivl_applicant) { FactoryBot.create(:individual_market_applicant, :with_person_name, :with_demographics, :with_eligibilities, application: ivl_application, family_member_id: subject.id) }
    let(:ivl_ivl_eligibility) { ivl_applicant.individual_market_eligibility }
    let(:ivl_alive_evidence) { FactoryBot.create(:alive_evidence, eligibility: ivl_ivl_eligibility) }
    let(:faa_application) do
      FactoryBot.create(
        :financial_assistance_application,
        family_id: family.id,
        aasm_state: 'determined',
        submitted_at: Time.now,
        assistance_year: TimeKeeper.date_of_record.year
      )
    end
    let(:faa_applicant) do
      FactoryBot.create(
        :financial_assistance_applicant,
        family_member_id: subject.id,
        person_hbx_id: person.hbx_id,
        application: faa_application
      )
    end
    let(:faa_ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: faa_applicant) }
    let(:faa_alive_evidence) { FactoryBot.create(:alive_evidence, :pending, eligibility: faa_ivl_eligibility) }

    before do
      ivl_application
      ivl_applicant
      faa_application
      faa_applicant
      ivl_ivl_eligibility
      faa_ivl_eligibility
      ivl_alive_evidence
      faa_alive_evidence
    end

    it 'should return the evidence from the latest determined application with the evidence key' do
      expect(subject.find_latest_determined_application_with_evidence_key("alive_evidence")).to eq faa_alive_evidence
    end

    it 'should return the faa evidence if that evidence is more recent' do
      ivl_alive_evidence.update_attributes(created_at: Time.now - 1.day)
      expect(subject.find_latest_determined_application_with_evidence_key("alive_evidence")).to eq faa_alive_evidence
    end

    it 'should return the ivl evidence if that evidence is more recent' do
      faa_alive_evidence.update_attributes(created_at: Time.now - 1.day)
      expect(subject.find_latest_determined_application_with_evidence_key("alive_evidence")).to eq ivl_alive_evidence
    end

    it 'should not return any evidences if the applications are not determined' do
      faa_application.update_attributes(aasm_state: 'draft')
      ivl_application.update_attributes(current_state: :initial)
      expect(subject.find_latest_determined_application_with_evidence_key(:alive_evidence)).to eq nil
    end
  end
end
