# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Families::IndividualMarketEligibilities::InitiateRenewal, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }
  let(:enrollment) do
    FactoryBot.create(
      :hbx_enrollment,
      :individual_unassisted,
      :health,
      :with_silver_health_product,
      aasm_state: enr_status,
      household: family.active_household,
      coverage_kind: 'health',
      effective_on: TimeKeeper.date_of_record.beginning_of_month,
      family: family
    )
  end
  let(:enr_status) { 'coverage_selected' }
  let(:enrollment_member) { FactoryBot.create(:hbx_enrollment_member, applicant_id: primary_applicant.id, hbx_enrollment: enrollment, coverage_start_on: enrollment.effective_on) }
  let(:fa_application) do
    FactoryBot.create(
      :financial_assistance_application,
      aasm_state: faa_app_status,
      assistance_year: TimeKeeper.date_of_record.year.next,
      effective_date: TimeKeeper.date_of_record.next_year.beginning_of_year,
      family_id: family.id
    )
  end

  let(:renewal_year) { TimeKeeper.date_of_record.year.next }

  let(:current_application) { FactoryBot.create(:individual_market_application, :determined, family_id: family.id) }
  let(:renewal_qhp_application) { FactoryBot.create(:individual_market_application, :renewal, current_state: renewal_state, family_id: family.id) }

  let(:enabled) { true }

  before do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(enabled)
    family.latest_application_gid = current_application.to_global_id.uri.to_s
    family.save!
  end

  describe '#call' do
    context 'with:
      - a family with active enrollment
      - no financial assistance renewal application
      - a renewal application of QHP type in determined state
      ' do

      let(:renewal_state) { :determined }

      before do
        renewal_qhp_application
        enrollment_member
      end

      it 'returns success without the family ID included' do
        result = subject.call(renewal_year: renewal_year)

        expect(result).to be_success
        expect(result.value!).not_to include(family.id)
      end
    end

    context 'with:
      - a family with active enrollment
      - no financial assistance renewal application
      - a renewal application of QHP type in initial state
      ' do

      let(:renewal_state) { :initial }

      before do
        renewal_qhp_application
        enrollment_member
      end

      it 'returns success with the family ID included' do
        result = subject.call(renewal_year: renewal_year)

        expect(result).to be_success
        expect(result.value!).to include(family.id)
      end
    end

    context 'with:
      - a family with active enrollment
      - no financial assistance renewal application
      ' do

      before do
        enrollment_member
      end

      it 'returns success with the family ID included' do
        result = subject.call(renewal_year: renewal_year)

        expect(result).to be_success
        expect(result.value!).to include(family.id)
      end
    end

    context 'with:
      - a family with active enrollment
      - a financial assistance renewal application in "applicants_update_required" state
      ' do

      let(:faa_app_status) { 'applicants_update_required' }

      before do
        enrollment_member
        fa_application
      end

      it 'returns success with the family ID included' do
        result = subject.call(renewal_year: renewal_year)

        expect(result).to be_success
        expect(result.value!).to include(family.id)
      end
    end

    context 'with:
      - a family with active enrollment
      - a financial assistance renewal application in "income_verification_extension_required" state
      ' do

      let(:faa_app_status) { 'income_verification_extension_required' }

      before do
        enrollment_member
        fa_application
      end

      it 'returns success with the family ID included' do
        result = subject.call(renewal_year: renewal_year)

        expect(result).to be_success
        expect(result.value!).to include(family.id)
      end
    end

    context 'with:
      - a family with active enrollment
      - a financial assistance renewal application in "determined" state
      ' do

      let(:faa_app_status) { 'determined' }

      before do
        enrollment_member
        fa_application
      end

      it 'returns success with the family ID included' do
        result = subject.call(renewal_year: renewal_year)

        expect(result).to be_success
        expect(result.value!).to include(family.id)
      end
    end

    context 'with:
      - a family with terminated enrollment
      - no financial assistance renewal application
      ' do

      let(:enr_status) { 'coverage_terminated' }

      before do
        enrollment_member
      end

      it 'returns success with an empty family ID list' do
        result = subject.call(renewal_year: renewal_year)

        expect(result).to be_success
        expect(result.value!).to be_empty
        expect(result.value!).not_to include(family.id)
      end
    end

    context 'with:
      - a family with no enrollment
      - no financial assistance renewal application
      ' do

      it 'returns success with an empty family ID list' do
        result = subject.call(renewal_year: renewal_year)

        expect(result).to be_success
        expect(result.value!).to be_empty
        expect(result.value!).not_to include(family.id)
      end
    end

    context 'with an invalid renewal year' do

      context 'when the renewal year is in the past' do
        let(:renewal_year) { TimeKeeper.date_of_record.year - 1 }

        it 'returns a failure with an error message' do
          result = subject.call(renewal_year: renewal_year)

          expect(result).to be_failure
          expect(result.failure).to eq(
            "Invalid renewal year: #{renewal_year}. Please provide a year greater than or equal to 2026."
          )
        end
      end

      context 'when the renewal year is a random string' do
        let(:renewal_year) { 'random_string' }

        it 'returns a failure with an error message' do
          result = subject.call(renewal_year: renewal_year)

          expect(result).to be_failure
          expect(result.failure).to eq(
            "Invalid renewal year: #{renewal_year}. Please provide a year greater than or equal to 2026."
          )
        end
      end

      context 'when the feature flag is disabled' do
        let(:enabled) { false }

        it 'returns a failure with an error message' do
          result = subject.call(renewal_year: renewal_year)

          expect(result).to be_failure
          expect(result.failure).to eq("QHP application feature is not enabled")
        end
      end
    end
  end
end
