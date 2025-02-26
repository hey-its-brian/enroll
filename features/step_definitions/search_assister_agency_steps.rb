# frozen_string_literal: true

When(/^Assister he enters an assister agency name and clicks on the search button$/) do
  page.find("input[type='search']").set(assister_agency_profile.legal_name)
end

Then(/^Assister he should see the one result with the agency name$/) do
  sleep(2)
  expect(page).to have_content(assister_agency_profile.legal_name)
end
