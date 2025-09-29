# frozen_string_literal: true

When(/^the user visits the Family Info page for the consumer's Financial Assistance application$/) do
  visit financial_assistance.edit_application_path(application.id)
end

Given(/^the consumer's application has all (complete|incomplete) applicants$/) do |status|
  allow_any_instance_of(FinancialAssistance::Applicant).to receive(:information_complete?).and_return(status == 'complete')
end

Given(/^the consumer's application has (valid|invalid) spousal tax information$/) do |status|
  allow_any_instance_of(FinancialAssistance::Application).to receive(:is_spousal_tax_info_valid?).and_return(status == 'valid')
end

Then(/^the user should see the Family Info title$/) do
  expect(page).to have_content('Family Information')
end

Then(/^the user can (.*) the spousal filing warning banner$/) do |should_not_see|
  should_not_see = should_not_see.include?('not')
  if should_not_see
    expect(page).not_to have_css('.alert-warning[data-cuke="spousal-filing-warning"]')
  else
    expect(page).to have_content(
      "You entered invalid information about the tax filing plans for people who are married. " \
      "One spouse cannot be listed as filing jointly while the other files separately or does not file, and spouses cannot claim each other as tax dependents. " \
      "To make updates, go to 'Tax info' for each person."
    )
  end
end

Then(/^the continue button should be (enabled|disabled)$/) do |state|
  continue_to_next_step_btn = find(IvlIapFamilyInformation.continue_to_next_step_btn)
  expect(continue_to_next_step_btn.matches_css?('.disabled')).to(state == 'enabled' ? be_falsey : be_truthy)
end

And(/^consumer clicks on pencil symbol next to primary person$/) do
  page.all('.fa-pencil-alt').first.click
end

And(/^consumer edits the dependent of the application$/) do
  sleep 2
  application.reload
  dependent = application.applicants.last
  FactoryBot.create(:person, hbx_id: dependent.person_hbx_id)
  find(IvlIapFamilyInformation.edit_dependent_btn).click
end

Then(/^consumer should see today date and clicks continue$/) do
  expect(page).to have_field('applicant_ssn', readonly: true)
  expect(page.find("input[name='jq_datepicker_ignore_applicant[dob]'")[:disabled]).to eq "true"
end

Given(/eligible immigration status checkbox feature is enabled/) do
  enable_feature :immigration_status_checkbox
end

And(/consumer chooses no for us citizen/) do
  find(IvlIapFamilyInformation.us_citizen_or_national_no_radiobtn).click
end

Then(/consumer should see the eligible immigration status checkbox/) do
  expect(page.find('#applicant_eligible_immigration_status')).to be_truthy
end
