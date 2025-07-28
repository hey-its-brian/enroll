# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Handlers::Families::FetchLatestDeterminedFAApplicationHbxIds, dbclean: :after_each do
  let!(:person) { FactoryBot.create(:person, hbx_id: "732020")}
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person)}
  let!(:determined_application) do
    FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: 'determined', hbx_id: "830293", effective_date: TimeKeeper.date_of_record.beginning_of_year, assistance_year: TimeKeeper.date_of_record.year)
  end
  let!(:draft_application) do
    FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: 'draft', hbx_id: "830294", effective_date: TimeKeeper.date_of_record.beginning_of_year, assistance_year: TimeKeeper.date_of_record.year)
  end


  let(:subject) { described_class.new }
  let(:params) do
    {
      additional_params: {
        assistance_year: TimeKeeper.date_of_record.year
      }
    }
  end

  # FinancialAssistance::Application.where(:"applicants.eligibilities".size => 24)

  describe '#call' do
    context 'when params are valid' do
      before do
        @result = subject.call(params)
      end

      it 'returns a mongo criteria' do
        expect(@result).to be_a(Array)
      end

      it 'should return the determined applications' do
        expect(@result).to include(determined_application.id)
      end
    end

    context 'when params are not valid' do
      it 'returns a failure monad when params is not a hash' do
        result = subject.call([])
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to eq('Invalid params provided')
      end

      it 'returns a failure monad when assistance_year is invalid' do
        result = subject.call(additional_params: { assistance_year: nil })
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to eq('Invalid params provided')
      end
    end

    context 'when one family ,
    - with two applications
    - one with origin migration exists' do
      let!(:determined_application_already_migrated) do
        FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: 'determined', hbx_id: "830293", effective_date: TimeKeeper.date_of_record.beginning_of_year, assistance_year: TimeKeeper.date_of_record.year)
      end

      before do
        determined_application_already_migrated.update!(origin: 'migration')
        @result = subject.call(params)
      end

      it 'should not return family' do
        expect(@result.present?).to be_falsey
      end
    end

    context 'when two families
    - one family without migrated data
    - other family with origin migration application exists' do
      let!(:person2) { FactoryBot.create(:person, hbx_id: "732021")}
      let!(:family2) { FactoryBot.create(:family, :with_primary_family_member, person: person2)}
      let!(:determined_application_for_family_2) do
        FactoryBot.create(:financial_assistance_application, family_id: family2.id, aasm_state: 'determined', hbx_id: "830293", effective_date: TimeKeeper.date_of_record.beginning_of_year, assistance_year: TimeKeeper.date_of_record.year)
      end
      let!(:determined_application_already_migrated) do
        FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: 'determined', hbx_id: "830293", effective_date: TimeKeeper.date_of_record.beginning_of_year, assistance_year: TimeKeeper.date_of_record.year)
      end

      before do
        determined_application_already_migrated.update!(origin: 'migration')
        @result = subject.call(params)
      end

      it 'should return one family' do
        expect(@result.present?).to be_truthy
        expect(@result).to include(determined_application_for_family_2.id)
      end
    end
  end
end
