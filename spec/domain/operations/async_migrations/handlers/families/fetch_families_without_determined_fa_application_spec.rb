# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Handlers::Families::FetchFamiliesWithoutDeterminedFAApplication, dbclean: :after_each do
  include Dry::Monads[:do, :result]

  let(:assistance_year) { TimeKeeper.date_of_record.year }
  let!(:person1) { FactoryBot.create(:person, hbx_id: "732020")}
  let!(:family1) { FactoryBot.create(:family, :with_primary_family_member, person: person1)}
  let(:person2) { FactoryBot.create(:person, hbx_id: "732021")}
  let(:family2) { FactoryBot.create(:family, :with_primary_family_member, person: person2)}
  let(:product) {FactoryBot.create(:benefit_markets_products_health_products_health_product, benefit_market_kind: :aca_individual, kind: :health, csr_variant_id: '01')}
  let(:effective_on) { TimeKeeper.date_of_record.beginning_of_year}

  let!(:determined_application) do
    FactoryBot.create(:financial_assistance_application, family_id: family1.id, aasm_state: 'determined', hbx_id: "830293", effective_date: TimeKeeper.date_of_record.beginning_of_year, assistance_year: assistance_year)
  end
  let!(:draft_application) do
    FactoryBot.create(:financial_assistance_application, family_id: family2.id, aasm_state: 'draft', hbx_id: "830294", effective_date: TimeKeeper.date_of_record.beginning_of_year, assistance_year: assistance_year)
  end

  let(:subject) { described_class.new }
  let(:params) do
    {
      additional_params: {
        assistance_year: assistance_year,
        data_type: 'Array'
      }
    }
  end

  describe '#call' do
    context 'when params are valid' do

      before do
        allow(subject).to receive(:fetch_families_with_latest_determined_fa_application).and_return(
          Success(::FinancialAssistance::Application.by_year(assistance_year).determined.pluck(:family_id))
        )
      end

      context 'family with shopping enrollment' do
        let(:shopping_enrollment) do
          FactoryBot.create(:hbx_enrollment,
                            family: family2,
                            effective_on: effective_on,
                            household: family2.active_household,
                            kind: "individual",
                            coverage_kind: "health",
                            aasm_state: 'shopping',
                            hbx_enrollment_members: [
                              FactoryBot.build(:hbx_enrollment_member, applicant_id: family2.primary_applicant.id, eligibility_date: effective_on, coverage_start_on: effective_on, is_subscriber: true)
                            ])
        end

        it 'returns failure' do
          shopping_enrollment
          result = subject.call(params)
          expect(result.count).to eql(0)
        end

      end

      context 'family with active enrollment' do
        before do
          active_enrollment
          @result = subject.call(params)
        end

        let(:active_enrollment) do
          FactoryBot.create(:hbx_enrollment,
                            family: family2,
                            household: family2.active_household,
                            kind: "individual",
                            coverage_kind: "health",
                            product: product,
                            aasm_state: 'coverage_selected',
                            effective_on: effective_on,
                            hbx_enrollment_members: [
                              FactoryBot.build(:hbx_enrollment_member, applicant_id: family2.primary_applicant.id, eligibility_date: effective_on, coverage_start_on: effective_on, is_subscriber: true)
                            ])
        end

        it 'should return families without determined fa applications' do
          expect(@result).to include(family2.id)
        end
      end
    end

    context 'when family already have qhp application' do
      before do
        active_enrollment
        qhp_application
        @result = subject.call(params)
      end

      let(:active_enrollment) do
        FactoryBot.create(:hbx_enrollment,
                          family: family2,
                          household: family2.active_household,
                          kind: "individual",
                          coverage_kind: "health",
                          product: product,
                          aasm_state: 'coverage_selected',
                          effective_on: effective_on,
                          hbx_enrollment_members: [
                            FactoryBot.build(:hbx_enrollment_member, applicant_id: family2.primary_applicant.id, eligibility_date: effective_on, coverage_start_on: effective_on, is_subscriber: true)
                          ])
      end
      let(:qhp_application) do
        FactoryBot.create(:individual_market_application, family: family2, current_state: 'determined', hbx_id: "830295", assistance_year: assistance_year)
      end

      it 'returns no application' do
        expect(@result.count).to eql(0)
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
  end

  describe "#call for data_type Array" do
    let(:active_enrollment) do
      FactoryBot.create(:hbx_enrollment,
                        family: family2,
                        household: family2.active_household,
                        kind: "individual",
                        coverage_kind: "health",
                        product: product,
                        aasm_state: 'coverage_selected',
                        effective_on: effective_on,
                        hbx_enrollment_members: [
                          FactoryBot.build(:hbx_enrollment_member, applicant_id: family2.primary_applicant.id, eligibility_date: effective_on, coverage_start_on: effective_on, is_subscriber: true)
                        ])
    end

    let(:params) do
      {
        additional_params: {
          assistance_year: assistance_year,
          data_type: 'Array'
        }
      }
    end

    before do
      allow(subject).to receive(:fetch_families_with_latest_determined_fa_application).and_return(
        Success(::FinancialAssistance::Application.by_year(assistance_year).determined.pluck(:family_id))
      )
    end

    context 'returns an array of family ids' do
      before do
        active_enrollment
        @result = subject.call(params)
      end

      it 'returns be valid' do
        expect(@result).to be_an(Array)
        expect(@result.first).to be_a(BSON::ObjectId)
      end
    end
  end
end




