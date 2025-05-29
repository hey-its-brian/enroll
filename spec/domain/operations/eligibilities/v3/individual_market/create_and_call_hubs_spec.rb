# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::Eligibilities::V3::IndividualMarket::CreateAndCallHubs, type: :model, dbclean: :after_each do

  before :all do
    DatabaseCleaner.clean
  end

  describe '#call' do
    context 'for financial assistance application' do
      context 'when application is valid' do
        let(:application) { FactoryBot.create(:financial_assistance_application) }
        let(:applicant) do
          FactoryBot.create(
            :financial_assistance_applicant,
            application: application,
            is_applying_coverage: applying_coverage,
            citizen_status: citizen_status,
            encrypted_ssn: encrypted_ssn,
            no_ssn: no_ssn,
            indian_tribe_member: indian_tribe_member
          )
        end
        let(:indian_tribe_member) { true }
        let(:encrypted_ssn) { SymmetricEncryption.encrypt('999999999') }
        let(:no_ssn) { '0' }
        let(:applying_coverage) { true }
        let(:citizen_status) { 'us_citizen' }

        it 'returns a success with the application' do
          expect(subject.call(application: applicant.application)).to be_success
        end

        it 'creates an IVL eligibility' do
          subject.call(application: applicant.application)
          expect(applicant.individual_market_eligibility).to be_present
        end

        it 'builds evidences for the IVL eligibility' do
          subject.call(application: applicant.application)
          expect(applicant.individual_market_eligibility.evidences).to be_present
        end
      end

      context 'when application is invalid' do
        let(:application) { 'testing application' }

        it 'returns a failure with an error message' do
          expect(subject.call(application: application).failure).to eq('Invalid application type: String')
        end
      end
    end
  end
end
