# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::Application::Build, dbclean: :after_each do
  subject { described_class.new }

  describe '#call' do
    let!(:family) { FactoryBot.create(:family, :with_primary_family_member_and_dependent) }
    let(:family_id) { family.id }
    let(:eligibility_params) do
      {
        key: :individual_market_eligibility,
        title: 'Individual Market Eligibility'
      }
    end
    let(:primary_applicant_params) do
      {
        family_member_id: family.family_members.first.id,
        is_primary_applicant: true,
        address_same_as_primary: false,

        person_name: {
          given_name: 'James',
          family_name: 'Doe'
        },
        demographics: {
          dob: Date.new(1980, 1, 1),
          gender: 'male',
          no_ssn: true
        },
        eligibilities: [eligibility_params],
        is_applying_coverage: true
      }
    end

    let(:dependent1_applicant_params) do
      {
        family_member_id: family.family_members.second.id,
        is_primary_applicant: false,
        address_same_as_primary: true,

        person_name: {
          given_name: 'John',
          family_name: 'Doe'
        },
        demographics: {
          dob: Date.new(2024, 12, 1),
          gender: 'male',
          no_ssn: true
        },
        eligibilities: [eligibility_params],
        is_applying_coverage: true
      }
    end

    let(:dependent2_applicant_params) do
      {
        family_member_id: family.family_members.last.id,
        is_primary_applicant: false,
        address_same_as_primary: true,

        person_name: {
          given_name: 'Alex',
          family_name: 'Doe'
        },
        demographics: {
          dob: Date.new(2024, 12, 1),
          gender: 'female',
          no_ssn: true
        },
        eligibilities: [eligibility_params],
        is_applying_coverage: true
      }
    end

    let(:valid_params) do
      {
        family_id: family_id,
        assistance_year: TimeKeeper.date_of_record.year,
        origin: :user,
        generation_reason: :manual,
        applicants: [primary_applicant_params, dependent1_applicant_params, dependent2_applicant_params]
      }
    end

    context 'with valid params' do
      let(:result) { subject.call(params: valid_params) }

      it 'is successful' do
        expect(result.success?).to be_truthy
      end

      it 'returns an application that is not persisted' do
        expect(result.success).to be_a_kind_of(IndividualMarket::Application)
        expect(result.success.persisted?).to be_falsey
      end

      it 'has the right number of applicants' do
        application = result.success
        expect(application.applicants.size).to be(3)
      end

      it 'has built relationships for dependents' do
        application = result.success
        expect(application.relationships.size).to eq(2)
        expect(application.relationships.last.kind).to eq('child')
      end

      it 'applicant has an Individual Market Eligibility' do
        application = result.success
        eligibility = application.applicants.first.eligibilities.first
        expect(eligibility).to be_a(Eligibilities::V3::Eligibility)
        expect(eligibility.key).to eq(:individual_market_eligibility)
        expect(eligibility.title).to eq('Individual Market Eligibility')
        expect(eligibility._type).to eq('Eligibilities::V3::IndividualMarketEligibility')
      end
    end
  end
end
