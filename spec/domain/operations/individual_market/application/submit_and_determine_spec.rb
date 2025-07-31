# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::Application::SubmitAndDetermine, dbclean: :after_each do
  subject { described_class.new }

  let(:application) { FactoryBot.create(:individual_market_application, :with_primary) }
  let(:primary_applicant) { application.primary_applicant }

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
      before do
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
    end
  end
end
