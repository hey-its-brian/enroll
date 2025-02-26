# frozen_string_literal: true

FactoryBot.define do
  factory :benefit_sponsors_accounts_assister_agency_account, class: 'BenefitSponsors::Accounts::AssisterAgencyAccount' do

    transient do
      assister_agency_profile { nil }
      benefit_sponsorship { nil }
    end

    start_on                { TimeKeeper.date_of_record }
    writing_agent           { FactoryBot.create(:assister_role)}

    after(:build) do |assister_agency_account, evaluator|
      assister_agency_account.assister_agency_profile = (evaluator.assister_agency_profile || FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile))
    end

    after(:build) do |assister_agency_account, evaluator|
      assister_agency_account.benefit_sponsorship = (evaluator.benefit_sponsorship || FactoryBot.build(:benefit_sponsors_benefit_sponsorship, :with_organization_cca_profile, site: BenefitSponsors::Site.by_site_key(:cca).first))
    end
  end
end
