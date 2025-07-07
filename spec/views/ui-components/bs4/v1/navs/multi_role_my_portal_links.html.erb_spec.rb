# frozen_string_literal: true

require 'rails_helper'

describe 'app/views/ui-components/bs4/v1/navs/_multi_role_my_portal_links.html.erb', dbclean: :after_each do

  describe 'with dual roles when one of the roles is consumer_role' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role) }
    let(:user) { FactoryBot.create(:user, person: person) }
    let(:site) { create(:benefit_sponsors_site, :with_benefit_market, :as_hbx_profile, site_key: ::EnrollRegistry[:enroll_app].settings(:site_key).item) }
    let(:broker_agency_organization) { FactoryBot.create(:benefit_sponsors_organizations_general_organization, :with_broker_agency_profile, site: site) }
    let(:broker_agency_id) { broker_agency_organization.broker_agency_profile.id }

    let(:auth_and_consent_url) { '/insured/consumer_role/ridp_agreement' }
    let(:broker_agency_registration_url) { '/benefit_sponsors/profiles/registrations/new?profile_type=broker_agency' }
    let(:broker_agency_portal_url) { "/benefit_sponsors/profiles/broker_agencies/broker_agency_profiles/#{broker_agency_id}?tab=home" }
    let(:resume_enrollment_url) { "/exchanges/agents/resume_enrollment?person_id=#{person.id}" }

    before do
      person.broker_agency_staff_roles.create!(
        {
          aasm_state: 'active',
          benefit_sponsors_broker_agency_profile_id: broker_agency_id
        }
      )

      person.consumer_role.update_attributes!(bookmark_url: auth_and_consent_url, identity_validation: 'na')
      allow(user).to receive(:consumer_identity_verified?).and_return(identity_verified)

      sign_in(user)
      render 'shared/my_portal_links'
    end

    context 'consumer role without RIPD' do
      let(:identity_verified) { false }

      context 'when the feature is disabled' do
        it 'does not have resume enrollment URL' do
          expect(rendered).not_to have_link('My Insured Portal', href: resume_enrollment_url)
        end

        it 'has broker agency portal link' do
          expect(rendered).to have_link(
            'My Broker Agency Portal', href: broker_agency_registration_url
          )
        end
      end
    end

    context 'consumer role with RIPD' do
      let(:identity_verified) { true }

      context 'when the feature is disabled' do
        it 'does not have resume enrollment URL' do
          expect(rendered).not_to have_link('My Insured Portal', href: resume_enrollment_url)
        end

        it 'has broker agency portal link' do
          expect(rendered).to have_link(
            'My Broker Agency Portal', href: broker_agency_registration_url
          )
        end
      end
    end
  end
end
