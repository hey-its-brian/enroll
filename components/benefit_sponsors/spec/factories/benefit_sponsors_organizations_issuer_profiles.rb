FactoryBot.define do
  factory :benefit_sponsors_organizations_issuer_profile, class: 'BenefitSponsors::Organizations::IssuerProfile' do

    transient do
      office_locations_count { 1 }
      assigned_site { nil }
      legal_name { "Blue Cross Blue Shield" }
      use_exempt_organization { false } # default to general org
    end

    after(:build) do |profile, evaluator|
      next if profile.organization.present?

      profile.organization = if evaluator.use_exempt_organization
                               if evaluator.assigned_site
                                 FactoryBot.build(
                                   :benefit_sponsors_organizations_exempt_organization,
                                   site: evaluator.assigned_site,
                                   legal_name: evaluator.legal_name
                                 )
                               else
                                 FactoryBot.build(
                                   :benefit_sponsors_organizations_exempt_organization,
                                   :with_me_site,
                                   legal_name: evaluator.legal_name
                                 )
                               end
                             elsif evaluator.assigned_site
                               FactoryBot.build(
                                 :benefit_sponsors_organizations_general_organization,
                                 site: evaluator.assigned_site,
                                 legal_name: evaluator.legal_name
                               )
                             else
                               FactoryBot.build(
                                 :benefit_sponsors_organizations_general_organization,
                                 :with_site,
                                 legal_name: evaluator.legal_name
                               )
                             end
    end

    after(:build) do |profile, evaluator|
      profile.office_locations << build_list(:benefit_sponsors_locations_office_location, evaluator.office_locations_count, :primary)
    end

    trait :with_exempt_organization do
      use_exempt_organization { true }
    end

    trait :kaiser_profile do
      legal_name        { "Kaiser Permanente" }
    end

    trait :anthm_profile do
      legal_name {"Anthem Blue Cross and Blue Shield"}
    end

    trait :default do
      legal_name { "Blue Cross Blue Shield" }
    end
  end
end
