# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BenefitSponsors::Observers::AssisterAgencyAccountObserver, type: :model, dbclean: :after_each do
  subject { BenefitSponsors::Observers::AssisterAgencyAccountObserver.new }

  let!(:rating_area) { create(:benefit_markets_locations_rating_area) }

  let(:site)  { create(:benefit_sponsors_site, :with_benefit_market, :as_hbx_profile, :cca) }
  let(:employer_organization)   { FactoryBot.build(:benefit_sponsors_organizations_general_organization, :with_aca_shop_cca_employer_profile, site: site) }
  let(:employer_profile) { employer_organization.profiles.first }
  let(:assister_agency_profile) { FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile, legal_name: 'Legal Name1', assigned_site: site) }
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsors_benefit_sponsorship, profile: employer_profile, benefit_market: site.benefit_markets.first) }

  before do
    allow(subject).to receive(:notify).exactly(1).times
  end

  context 'when employer hired a assister' do

    let(:account) { build :benefit_sponsors_accounts_assister_agency_account, assister_agency_profile: assister_agency_profile, benefit_sponsorship: benefit_sponsorship }

    before do
      subject.assister_hired?(account)
      subject.assister_fired?(account)
    end

    it 'should notify hired event' do
      sponsor = account.benefit_sponsorship.profile
      expect(subject).to have_received(:notify).with("acapi.info.events.employer.assister_added", {employer_id: sponsor.hbx_id, event_name: "assister_added"})
    end

    it 'should not notify fired event' do
      sponsor = account.benefit_sponsorship.profile
      expect(subject).not_to have_received(:notify).with("acapi.info.events.employer.assister_terminated", {employer_id: sponsor.hbx_id, event_name: "assister_terminated"})
    end
  end

  context 'when a family account hires a assister agency' do
    let(:assister_role) { FactoryBot.create(:assister_role, :aasm_state => 'active', assister_agency_profile: assister_agency_profile) }
    let(:account) { build :benefit_sponsors_accounts_assister_agency_account, benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id, writing_agent_id: assister_role.id}

    before do
      subject.assister_hired?(account)
      subject.assister_fired?(account)
    end

    it 'should not notify hired event' do
      expect(subject).not_to have_received(:notify).with("acapi.info.events.employer.assister_added", {employer_id: employer_profile.hbx_id, event_name: "assister_added"})
    end

    it 'should not notify fired event' do
      expect(subject).not_to have_received(:notify).with("acapi.info.events.employer.assister_terminated", {employer_id: employer_profile.hbx_id, event_name: "assister_terminated"})
    end
  end

  context 'when employer fired a assister' do

    let(:account) { create :benefit_sponsors_accounts_assister_agency_account, assister_agency_profile: assister_agency_profile, benefit_sponsorship: benefit_sponsorship }

    before do
      account.assign_attributes({is_active: false, end_on: TimeKeeper.date_of_record})

      subject.assister_hired?(account)
      subject.assister_fired?(account)
    end

    it 'should notify fired event' do
      sponsor = account.benefit_sponsorship.profile
      expect(subject).to have_received(:notify).with("acapi.info.events.employer.assister_terminated", {employer_id: sponsor.hbx_id, event_name: "assister_terminated"})
    end

    it 'should not notify hired event' do
      sponsor = account.benefit_sponsorship.profile
      expect(subject).not_to have_received(:notify).with("acapi.info.events.employer.assister_added", {employer_id: sponsor.hbx_id, event_name: "assister_added"})
    end
  end
end
