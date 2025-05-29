# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::ApplicationsController, dbclean: :after_each, type: :controller do
  routes { FinancialAssistance::Engine.routes }

  before :all do
    DatabaseCleaner.clean
  end

  let(:person1) { FactoryBot.create(:person, :with_consumer_role)}
  let(:user) { FactoryBot.create(:user, person: person1) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person1) }

  let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }
  let(:applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      application: application,
      is_applying_coverage: applying_coverage,
      citizen_status: citizen_status,
      encrypted_ssn: encrypted_ssn,
      no_ssn: no_ssn,
      indian_tribe_member: indian_tribe_member,
      family_member_id: family.primary_family_member.id,
      person_hbx_id: person1.hbx_id
    )
  end
  let(:indian_tribe_member) { true }
  let(:encrypted_ssn) { SymmetricEncryption.encrypt('999999999') }
  let(:no_ssn) { '0' }
  let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:individual_market_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
  let(:applying_coverage) { true }
  let(:citizen_status) { 'us_citizen' }

  before do
    family.primary_person.consumer_role.move_identity_documents_to_verified
    sign_in(user)
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(enabled)
    get :preferences, params: { id: applicant.application.id }
  end

  describe 'GET #preferences' do
    context 'when qhp_application feature is enabled' do
      let(:enabled) { true }

      it 'renders the preferences template' do
        expect(response).to render_template(:preferences)
      end

      it 'creates the IVL eligibility and evidences' do
        expect(applicant.reload.individual_market_eligibility).to be_present
        expect(applicant.individual_market_eligibility.evidences).not_to be_empty
      end
    end

    context 'when qhp_application feature is disabled' do
      let(:enabled) { false }

      it 'renders the preferences template' do
        expect(response).to render_template(:preferences)
      end

      it 'does not create IVL eligibility and evidences' do
        expect(applicant.reload.individual_market_eligibility).to be_nil
      end
    end
  end
end
