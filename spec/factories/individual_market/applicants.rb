# frozen_string_literal: true

FactoryBot.define do
  factory :individual_market_applicant, class: 'IndividualMarket::Applicant' do
    association :application, factory: :individual_market_application

    family_member_id { BSON::ObjectId.new }
    is_primary_applicant { true }
    address_same_as_primary { false }
    is_applying_coverage { true }
    is_homeless { false }

    trait :dependent do
      family_member_id { BSON::ObjectId.new }
      is_primary_applicant { false }
      address_same_as_primary { true }
      is_applying_coverage { true }
      is_homeless { false }
    end

    trait :with_person_name do
      after(:build) do |applicant|
        applicant.person_name = FactoryBot.build(:person_name)
      end
    end

    trait :with_demographics do
      after(:build) do |applicant|
        applicant.demographics = FactoryBot.build(:individual_market_demographics)
      end
    end

    trait :with_ivl_eligibility do
      after(:build) do |applicant|
        applicant.eligibilities << FactoryBot.build(:individual_market_eligibility)
      end
    end

    trait :with_aptc_csr_eligibility do
      after(:build) do |applicant|
        applicant.eligibilities << FactoryBot.build(:aptc_csr_eligibility)
      end
    end

    trait :with_eligibilities do
      after(:build) do |applicant|
        applicant.eligibilities << FactoryBot.build(:individual_market_eligibility)
        applicant.eligibilities << FactoryBot.build(:aptc_csr_eligibility)
      end
    end

    trait :with_work_address do
      after(:build) do |applicant|
        applicant.addresses << FactoryBot.build(:location_address, :work_kind)
      end
    end

    trait :with_mailing_address do
      after(:build) do |applicant|
        applicant.addresses << FactoryBot.build(:location_address, :mailing_kind)
      end
    end

    trait :with_home_address do
      after(:build) do |applicant|
        applicant.addresses << FactoryBot.build(:location_address)
      end
    end

    trait :with_phone_number do
      after(:build) do |applicant|
        applicant.phones << FactoryBot.build(:location_phone)
      end
    end

    trait :with_email do
      after(:build) do |applicant|
        applicant.emails << FactoryBot.build(:location_email)
      end
    end

  end
end
