# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::Application::SubmitAndDetermine, dbclean: :after_each do
  subject { described_class.new }

  let(:application) { FactoryBot.create(:individual_market_application, :with_primary) }
  let(:primary_applicant) { application.primary_applicant }
  let(:family) { application.family }
  let(:rating_area) { FactoryBot.create_default(:benefit_markets_locations_rating_area) }
  let(:person) { FactoryBot.create(:person) }
  let(:consumer_role) { FactoryBot.create(:consumer_role, person: person) }
  let(:tax_household) { FactoryBot.create(:tax_household, household: family.active_household, effective_ending_on: nil, effective_starting_on: TimeKeeper.date_of_record.beginning_of_year) }

  describe '#call' do
    context 'with invalid params' do
      context 'when application is not provided' do
        it 'returns failure' do
          result = subject.call(application: nil)
          expect(result).to be_failure
          expect(result.failure).to eq('Invalid application type. Expected IndividualMarket::Application.')
        end
      end

      context 'when application is not initial' do
        it 'returns failure' do
          application.update_attributes(current_state: 'submitted')
          result = subject.call(application: application)
          expect(result).to be_failure
          expect(result.failure).to eq('Invalid application is not initial.')
        end
      end

      context 'when application does not have a family' do
        it 'returns failure' do
          application.update_attributes(family_id: nil)
          result = subject.call(application: application)
          expect(result).to be_failure
          expect(result.failure).to include('Invalid Family for given application with hbx_id')
        end
      end
    end

    context 'with valid application' do
      let(:existing_enrollment) do
        FactoryBot.create(
          :hbx_enrollment,
          :individual_unassisted,
          :with_silver_health_product,
          family: family,
          household: family.active_household,
          coverage_kind: 'health',
          consumer_role: consumer_role,
          effective_on: TimeKeeper.date_of_record.beginning_of_year,
          rating_area_id: rating_area.id
        )
      end

      let(:new_effective_date) { Insured::Factories::SelfServiceFactory.new_enrollment_effective_on_date(existing_enrollment, nil) }

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:apply_aggregate_to_enrollment).and_return(true)
        existing_enrollment
        tax_household
        primary_applicant.update_attributes(demographics: {no_ssn: 'false', ssn: '123456789', encrypted_ssn: SymmetricEncryption.encrypt('123456789'), indian_tribe_member: 'true'})
        @result = subject.call(application: application)
        application.reload
        primary_applicant.reload
      end

      it 'returns success' do
        expect(@result).to be_success
      end

      it 'should return an application' do
        expect(@result.success.is_a?(IndividualMarket::Application)).to be_truthy
      end

      it 'application current state is determined' do
        expect(application.current_state).to eq(:determined)
      end

      it 'application has been submitted' do
        expect(application.submitted_at).to be_present
      end

      it 'should have state histories showing the application was submitted and determined' do
        expect(application.state_histories.map(&:to_state)).to include(:submitted, :determined)
      end

      it 'has updated the family' do
        expect(application.family_updated_at).to be_present
      end

      it 'has created individual market determinations for each applicant' do
        expect(primary_applicant.individual_market_eligibility.determinations.count).to eq(2)
      end

      it 'has generated evidences for each applicant' do
        # AmericanIndianEvidence, SocialSecurityNumberEvidence, AliveEvidence, CitizenshipEvidence
        expect(primary_applicant.individual_market_eligibility.evidences.count).to eq(4)
      end

      it "terminates the existing aptc enrollment if the new effective date year matches enrollment effective on year" do
        if new_effective_date.year == existing_enrollment.effective_on.year
          existing_enrollment.reload
          expect(existing_enrollment.aasm_state).to eq('coverage_terminated')
        end
      end

      it 'generates new enrollments' do
        family.reload
        if new_effective_date.year == existing_enrollment.effective_on.year
          expect(family.active_household.hbx_enrollments.count).to eq(2)
          expect(family.active_household.hbx_enrollments.last.aasm_state).to eq('coverage_selected')
        else
          expect(family.active_household.hbx_enrollments.count).to eq(1)
        end
      end

      context 'when attempting to send qhp notifications for a renewal application' do
        it 'returns Success with no notifications message' do
          application.update_attributes(is_renewal: true)
          result = subject.send(:trigger_notifications, application)
          expect(result).to be_success
          expect(result.success).to eq('No notifications for renewals.')
        end
      end

      context 'when attempting to send qhp notifications for a non-applicant only application' do
        before do
          # remove cached var
          application.remove_instance_variable(:@non_applicants)

          # simulate non-applicant only application determination
          application.applicants.each { |applicant| applicant.update_attributes(is_applying_coverage: false) }
          subject.send(:determine_applicants, application)

          @notification_trigger = subject.send(:trigger_notifications, application)
        end

        it 'returns Success with no notifications message' do
          expect(@notification_trigger).to be_success
          expect(@notification_trigger.success).to eq('No notifications for applications with only non-applicants.')
        end
      end
    end

    context 'when family update operation fails' do
      before do
        failure_result = Dry::Monads::Result::Failure.new("Family update failed")
        mock_operation = double('mock_operation', call: failure_result)
        allow(Operations::IndividualMarket::Families::CreateOrUpdate).to receive(:new).and_return(mock_operation)
      end

      it 'returns failure' do
        result = subject.call(application: application)
        expect(result).to be_failure
        expect(result.failure).to eq("Family update failed")
      end

      it 'sets application to failed_family_sync state' do
        subject.call(application: application)
        application.reload
        expect(application.current_state).to eq(:family_sync_failed)
      end
    end

    context 'with an existing aptc enrollment' do
      let(:existing_aptc_enrollment) do
        FactoryBot.create(
          :hbx_enrollment,
          :individual_aptc,
          :with_silver_health_product,
          family: family,
          household: family.active_household,
          coverage_kind: 'health',
          consumer_role: consumer_role,
          effective_on: TimeKeeper.date_of_record.beginning_of_year,
          rating_area_id: rating_area.id,
          aasm_state: 'coverage_selected'
        )
      end

      let(:new_effective_date) { Insured::Factories::SelfServiceFactory.new_enrollment_effective_on_date(existing_aptc_enrollment, nil) }

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:apply_aggregate_to_enrollment).and_return(true)
        existing_aptc_enrollment
        primary_applicant.update_attributes(demographics: {no_ssn: 'false', ssn: '123456789', encrypted_ssn: SymmetricEncryption.encrypt('123456789'), indian_tribe_member: 'true'})
        @result = subject.call(application: application)
        application.reload
        primary_applicant.reload
      end

      it "terminates the existing aptc enrollment if the new effective date year matches enrollment effective on year" do
        if new_effective_date.year == existing_aptc_enrollment.effective_on.year
          existing_aptc_enrollment.reload
          expect(existing_aptc_enrollment.aasm_state).to eq('coverage_terminated')
        end
      end

      it 'generates new enrollment' do
        # if the existing enrollment was created after December 1,
        # it will have a next year effective date and no new enrollments will generate
        family.reload
        if new_effective_date.year == existing_aptc_enrollment.effective_on.year
          expect(family.active_household.hbx_enrollments.count).to eq(2)
        else
          expect(family.active_household.hbx_enrollments.count).to eq(1)
        end
      end

      it 'applies no aptc to the new enrollment' do
        family.reload
        expect(family.active_household.hbx_enrollments.last.applied_aptc_amount).to eq(0) if new_effective_date.year == existing_aptc_enrollment.effective_on.year
      end
    end

    context 'with an existing aptc enrollment with catastrophic plan' do
      let(:existing_aptc_enrollment) do
        FactoryBot.create(
          :hbx_enrollment,
          :individual_aptc,
          :with_silver_health_product,
          family: family,
          household: family.active_household,
          coverage_kind: 'health',
          consumer_role: consumer_role,
          effective_on: TimeKeeper.date_of_record.beginning_of_year,
          rating_area_id: rating_area.id,
          aasm_state: 'coverage_selected'
        )
      end

      let(:new_effective_date) { Insured::Factories::SelfServiceFactory.new_enrollment_effective_on_date(existing_aptc_enrollment, nil) }

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:apply_aggregate_to_enrollment).and_return(true)
        existing_aptc_enrollment.product.update(metal_level_kind: :catastrophic)
        primary_applicant.update_attributes(demographics: {no_ssn: 'false', ssn: '123456789', encrypted_ssn: SymmetricEncryption.encrypt('123456789'), indian_tribe_member: 'true'})
        @result = subject.call(application: application)
        application.reload
        primary_applicant.reload
      end

      it "terminates the existing aptc enrollment if the new effective date year matches enrollment effective on year" do
        if new_effective_date.year == existing_aptc_enrollment.effective_on.year
          existing_aptc_enrollment.reload
          expect(existing_aptc_enrollment.aasm_state).to eq('coverage_terminated')
        end
      end

      it 'generates new enrollment' do
        # if the existing enrollment was created after December 1,
        # it will have a next year effective date and no new enrollments will generate
        family.reload
        if new_effective_date.year == existing_aptc_enrollment.effective_on.year
          expect(family.active_household.hbx_enrollments.count).to eq(2)
        else
          expect(family.active_household.hbx_enrollments.count).to eq(1)
        end
      end

      it 'applies no aptc to the new enrollment' do
        family.reload
        expect(family.active_household.hbx_enrollments.last.applied_aptc_amount).to eq(0) if new_effective_date.year == existing_aptc_enrollment.effective_on.year
      end
    end
  end
end
