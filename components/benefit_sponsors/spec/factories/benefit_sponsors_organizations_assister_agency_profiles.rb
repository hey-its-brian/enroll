# frozen_string_literal: true

FactoryBot.define do
  factory :benefit_sponsors_organizations_assister_agency_profile, class: 'BenefitSponsors::Organizations::AssisterAgencyProfile' do

    market_kind { is_shop_market_enabled? ? :shop : :individual }
    corporate_aoid { "0989898981" }
    ach_routing_number { '123456789' }
    ach_account_number { '9999999999999999' }
    association :primary_assister_role, factory: :assister_role
    transient do
      legal_name { nil }
      office_locations_count { 1 }
      assigned_site { nil }
    end

    after(:build) do |profile, evaluator|
      profile.office_locations << build_list(:benefit_sponsors_locations_office_location, evaluator.office_locations_count, :primary)

      if profile.organization.blank?
        profile.organization = if evaluator.assigned_site
                                 FactoryBot.build(:benefit_sponsors_organizations_general_organization, legal_name: evaluator.legal_name, site: evaluator.assigned_site)
                               else
                                 FactoryBot.build(:benefit_sponsors_organizations_general_organization, :with_site)
                               end
      end

      assister_role = profile.primary_assister_role
      if assister_role.present? && assister_role.benefit_sponsors_assister_agency_profile_id.blank?
        assister_role.benefit_sponsors_assister_agency_profile_id = profile.id
        assister_role.save! && profile.save!
      end
    end
  end
end
