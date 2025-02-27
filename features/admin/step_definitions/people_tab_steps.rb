# frozen_string_literal: true

Given(/a consumer without a family exists/) do
  FactoryBot.create(:person)
end

Given(/that a person exists with (.*) as (.*)/) do |key, value|
  field = key.downcase.gsub(' ', '_')
  FactoryBot.create(:person, **{field => value})
end

When(/^Hbx Admin navigates to the People tab$/) do
  links = page.all('a')
  persons_dropdown = links.detect { |link| link.text == "People" }
  persons_dropdown.click
end

When(/the Hbx searches by (.*)/) do |query|
  find('input[type="search"]').set(query)
end

Then(/^the Hbx Admin should see the People title$/) do
  expect(page).to have_selector('h1', text: 'People')
end

Then(/^the Hbx Admin should see the name, dob, hbx id, roles, and actions columns$/) do
  within('table.effective-datatable thead') do
    headers = all('th')
    expected_headers = ['Name', 'DOB', 'HBX ID', 'Active Roles', 'Actions']
    headers.zip(expected_headers).each do |header, expected_header|
      expect(header).to have_content(expected_header)
    end
  end
end

Then("the Hbx Admin should not see filter options") do
  expect(page).not_to have_selector('.custom_filter')
end

Then("the Hbx Admin should not see export options") do
  links = page.all('p')
  export_option_texts = ['Excel', 'CSV']
  links.each do |link|
    expect(link.text).not_to be_in(export_option_texts)
  end
end

Then(/the Hbx Admin will see (.*) role in the role column/) do |role|
  user_row = page.all('table tbody tr')[1] # row at first index represents the admin person
  within user_row do
    expect(page).to have_selector('td:nth-child(4)', text: role)
  end
end

Then(/the Hbx Admin will see the user/) do
  within('table tbody') do
    expect(page).to have_selector('tr', count: 1)
  end
end

Then(/the Hbx Admin should see no actions for the consumer/) do
  expect(page.body).to include('No actions available')
end
