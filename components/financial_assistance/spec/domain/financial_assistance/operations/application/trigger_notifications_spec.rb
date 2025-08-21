# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Operations::Application::TriggerNotifications, dbclean: :after_each do

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: app_state) }
  let(:applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      :with_home_address,
      is_primary_applicant: true,
      application: application,
      family_member_id: family.primary_applicant.id,
      first_name: person.first_name,
      last_name: person.last_name,
      dob: person.dob,
      ssn: person.ssn,
      is_totally_ineligible: applicant_totally_ineligible
    )
  end

  let(:application_entity) { ::Operations::Fdsh::BuildAndValidateApplicationPayload.new.call(application).success }

  let(:hbx_profile) {FactoryBot.create(:hbx_profile)}
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }

  before :each do
    benefit_sponsorship
    allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:totally_ineligible_notice).and_return(enabled)
  end

  let(:enabled) { true }
  let(:applicant_totally_ineligible) { true }
  let(:app_state) { 'determined' }

  describe '#call' do
    context 'when:
      - application is FinancialAssistance::Application
      - application_entity is AcaEntities::MagiMedicaid::Application
      - application is in determined state
      - application has totally ineligible members
      - :totally_ineligible_notice feature is enabled
      ' do

      before do
        applicant
        application_entity
      end

      it 'returns success' do
        expect(subject.call(application: application, application_entity: application_entity).success?).to be_truthy
      end
    end

    context 'when:
      - application is FinancialAssistance::Application
      - application_entity is AcaEntities::MagiMedicaid::Application
      - application is in determined state
      - application has totally ineligible members
      - :totally_ineligible_notice feature is not enabled
      ' do

      let(:enabled) { false }

      before do
        applicant
        application_entity
      end

      it 'returns success' do
        expect(subject.call(application: application, application_entity: application_entity).success?).to be_truthy
      end
    end

    context 'when:
      - application is FinancialAssistance::Application
      - application_entity is AcaEntities::MagiMedicaid::Application
      - application is in determined state
      - application does not have totally ineligible members
      ' do

      let(:applicant_totally_ineligible) { false }

      before do
        applicant
        application_entity
      end

      it 'returns success' do
        expect(subject.call(application: application, application_entity: application_entity).success?).to be_truthy
      end
    end

    context 'when:
      - application is FinancialAssistance::Application
      - application_entity is AcaEntities::MagiMedicaid::Application
      - application is not in determined state
      ' do

      let(:app_state) { 'draft' }

      before do
        applicant
        application_entity
      end

      it 'returns failure' do
        expect(subject.call(application: application, application_entity: application_entity).failure).to eq(
          'Application is expected to be determined to trigger any notifications.'
        )
      end
    end

    context 'when:
      - application is not of type FinancialAssistance::Application
      - application_entity is AcaEntities::MagiMedicaid::Application
      ' do

      it 'returns failure' do
        expect(subject.call(application: 'application', application_entity: application_entity).failure).to eq(
          'Application is expected to be of type FinancialAssistance::Application.'
        )
      end
    end

    context 'when:
      - application is FinancialAssistance::Application
      - application_entity is not of type AcaEntities::MagiMedicaid::Application
      ' do

      it 'returns failure' do
        expect(subject.call(application: application, application_entity: 'application_entity').failure).to eq(
          'Application entity is expected to be of type AcaEntities::MagiMedicaid::Application.'
        )
      end
    end
  end
end
