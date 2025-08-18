# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::Applications::Renewals::Create, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }

  let(:current_application) { FactoryBot.create(:individual_market_application, :initial, family_id: family.id) }
  let(:renewal_qhp_application) { FactoryBot.create(:individual_market_application, :initial_renewal, family_id: family.id) }

  let(:enrollment) do
    FactoryBot.create(
      :hbx_enrollment,
      :individual_unassisted,
      :health,
      :with_silver_health_product,
      household: family.active_household,
      coverage_kind: 'health',
      effective_on: TimeKeeper.date_of_record.beginning_of_month,
      family: family
    )
  end
  let(:enrollment_member) { FactoryBot.create(:hbx_enrollment_member, applicant_id: primary_applicant.id, hbx_enrollment: enrollment, coverage_start_on: enrollment.effective_on) }

  let(:fa_application) do
    FactoryBot.create(
      :financial_assistance_application,
      aasm_state: faa_app_status,
      assistance_year: TimeKeeper.date_of_record.year.next,
      effective_date: TimeKeeper.date_of_record.next_year.beginning_of_year,
      family_id: family_id
    )
  end

  let(:result) { subject.call(family_id: family_id, renewal_year: renewal_year) }

  describe '#call' do
    context 'with:
      - with valid family
      - without a financial assistance application for the renewal year
      - application with type of QHP exists for current year
      - effectuated enrollment
      ' do

      before :each do
        current_application
        renewal_qhp_application
        enrollment_member
        result
      end

      let(:family_id) { family.id.to_s }
      let(:renewal_year) { TimeKeeper.date_of_record.year.next }

      it 'returns the renewal application' do
        expect(result).to be_success
        expect(result.success).to be_a(IndividualMarket::Application)
        expect(result.success).to eq(renewal_qhp_application)
      end

      it 'does not create a new application' do
        expect(result).to be_success
        expect(
          ::IndividualMarket::Application.where(
            assistance_year: renewal_year,
            family_id: family.id,
            is_renewal: true
          ).count
        ).to eq(1)
      end

      it 'does not cancel the current application' do
        expect(current_application.reload.current_state).to eq(:initial)
      end
    end

    context 'with:
      - with valid family
      - with a QHP application for renewal year
      - application with type of QHP exists for current year
      - effectuated enrollment
      ' do

      before :each do
        current_application
        enrollment_member
        result
      end

      let(:family_id) { family.id.to_s }
      let(:renewal_year) { TimeKeeper.date_of_record.year.next }

      it 'creates a renewal application' do
        expect(result).to be_success
        expect(result.success).to be_a(IndividualMarket::Application)
        expect(result.success).to have_attributes(
          current_state: :initial,
          family_id: family.id,
          assistance_year: renewal_year,
          is_renewal: true,
          generation_reason: :renewal,
          origin: :system
        )
      end

      it 'returns a persisted application' do
        expect(result).to be_success
        expect(result.success).to be_a(IndividualMarket::Application)
        expect(result.success).to be_persisted
      end

      it 'does not cancel the current application' do
        expect(current_application.reload.current_state).to eq(:initial)
      end
    end

    context 'with:
      - with valid family
      - without a financial assistance application for the renewal year
      - without an application for current year
      - with an effectuated enrollment
      ' do

      before :each do
        enrollment_member
        result
      end

      let(:family_id) { family.id.to_s }
      let(:renewal_year) { TimeKeeper.date_of_record.year.next }

      it 'creates a renewal application' do
        expect(result).to be_success
        expect(result.success).to be_a(IndividualMarket::Application)
        expect(result.success).to have_attributes(
          current_state: :initial,
          family_id: family.id,
          assistance_year: renewal_year,
          is_renewal: true,
          generation_reason: :renewal,
          origin: :system
        )
      end

      it 'returns a persisted application' do
        expect(result).to be_success
        expect(result.success).to be_a(IndividualMarket::Application)
        expect(result.success).to be_persisted
      end
    end

    context 'with:
      - with valid family
      - with a financial assistance application for the renewal year in applicants_update_required state
      - without an application for current year
      - with an effectuated enrollment
      ' do

      let(:faa_app_status) { 'applicants_update_required' }

      before :each do
        fa_application
        enrollment_member
        result
      end

      let(:family_id) { family.id.to_s }
      let(:renewal_year) { TimeKeeper.date_of_record.year.next }

      it 'creates a renewal application' do
        expect(result).to be_success
        expect(result.success).to be_a(IndividualMarket::Application)
        expect(result.success).to have_attributes(
          current_state: :initial,
          family_id: family.id,
          assistance_year: renewal_year,
          is_renewal: true,
          generation_reason: :renewal,
          origin: :system
        )
      end

      it 'returns a persisted application' do
        expect(result).to be_success
        expect(result.success).to be_a(IndividualMarket::Application)
        expect(result.success).to be_persisted
      end
    end

    context 'with:
      - with valid family
      - with a financial assistance application for the renewal year in income_verification_extension_required state
      - without an application for current year
      - with an effectuated enrollment
      ' do

      let(:faa_app_status) { 'income_verification_extension_required' }

      before :each do
        fa_application
        enrollment_member
        result
      end

      let(:family_id) { family.id.to_s }
      let(:renewal_year) { TimeKeeper.date_of_record.year.next }

      it 'creates a renewal application' do
        expect(result).to be_success
        expect(result.success).to be_a(IndividualMarket::Application)
        expect(result.success).to have_attributes(
          current_state: :initial,
          family_id: family.id,
          assistance_year: renewal_year,
          is_renewal: true,
          generation_reason: :renewal,
          origin: :system
        )
      end

      it 'returns a persisted application' do
        expect(result).to be_success
        expect(result.success).to be_a(IndividualMarket::Application)
        expect(result.success).to be_persisted
      end
    end

    context 'with:
      - with valid family
      - with a financial assistance application for the renewal year in determined state
      - without an application for current year
      - with an effectuated enrollment
      ' do

      let(:faa_app_status) { 'determined' }

      before :each do
        fa_application
        enrollment_member
        result
      end

      let(:family_id) { family.id.to_s }
      let(:renewal_year) { TimeKeeper.date_of_record.year.next }

      it 'returns a failure with a message' do
        expect(result).to be_failure
        expect(result.failure).to eq(
          "Family with #{family.id} already has Financial Assistance application for the renewal year #{renewal_year}"
        )
      end
    end

    context 'with:
      - with valid family
      - without a financial assistance application for the renewal year
      - without an application for current year
      - without effectuated enrollment
      ' do

      before :each do
        result
      end

      let(:family_id) { family.id.to_s }
      let(:renewal_year) { TimeKeeper.date_of_record.year.next }

      it 'returns a failure with a message' do
        expect(result).to be_failure
        expect(result.failure).to eq("Family with #{family_id} does not have any effectuated enrollments")
      end
    end

    context 'with:
      - without a valid family
      - without a financial assistance application for the renewal year
      - without an application for current year
      - without effectuated enrollment
      ' do

      before :each do
        result
      end

      let(:family_id) { 'bad_family' }
      let(:renewal_year) { TimeKeeper.date_of_record.year.next }

      it 'returns a failure with a message' do
        expect(result).to be_failure
        expect(result.failure).to eq("Family with id #{family_id} not found")
      end
    end

    context 'with:
      - with a valid family
      - with an invalid renewal year
      - without a financial assistance application for the renewal year
      - without an application for current year
      - without effectuated enrollment
      ' do

      before :each do
        result
      end

      let(:family_id) { family.id.to_s }
      let(:renewal_year) { '3487kjsdbf' }

      it 'returns a failure with a message' do
        expect(result).to be_failure
        expect(result.failure).to eq("Invalid renewal year: #{renewal_year}")
      end
    end
  end
end
