# frozen_string_literal: true

FactoryBot.define do
  factory :assister_agency_account do
    employer_profile
    start_on                { TimeKeeper.date_of_record }
    assister_agency_profile   { FactoryBot.create(:assister_agency_profile)}
    writing_agent           { FactoryBot.create(:assister_role)}
  end

end
