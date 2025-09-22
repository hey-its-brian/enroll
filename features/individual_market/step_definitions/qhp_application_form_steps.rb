# frozen_string_literal: true

And(/^user enters qhp applicant name, ssn, gender and dob$/) do
  fill_in IndividualMarket::ApplicantForm.applicant_first_name, :with => 'johnson', wait: 5
  fill_in IndividualMarket::ApplicantForm.applicant_last_name, :with => 'smith'
  fill_in IndividualMarket::ApplicantForm.applicant_form_dob, :with => '10/10/1984'
  click_outside_datepicker(l10n('family_information'))
  fill_in IndividualMarket::ApplicantForm.applicant_form_ssn, :with => '324457543'

  select 'Male', from: IndividualMarket::ApplicantForm.applicant_gender_select
end

And(/^user enters qhp applicant name, gender, dob and checks no ssn$/) do
  fill_in IndividualMarket::ApplicantForm.applicant_first_name, :with => 'johnson', wait: 5
  fill_in IndividualMarket::ApplicantForm.applicant_last_name, :with => 'smith'
  fill_in IndividualMarket::ApplicantForm.applicant_form_dob, :with => '10/10/1984'
  click_outside_datepicker(l10n('family_information'))
  check IndividualMarket::ApplicantForm.applicant_form_no_ssn

  select 'Male', from: IndividualMarket::ApplicantForm.applicant_gender_select
end

And(/user selects yes for qhp applicant's coverage requirement$/) do
  choose(IndividualMarket::ApplicantForm.is_applying_coverage_true, allow_label_click: true)
end

And(/user selects no for qhp applicant's coverage requirement$/) do
  choose(IndividualMarket::ApplicantForm.is_applying_coverage_false, allow_label_click: true)
end

And(/^user selects no for qhp applicant's incarcerated status$/) do
  choose(IndividualMarket::ApplicantForm.radio_incarcerated, option: 'false')
end

And(/^user selects yes for qhp applicant's incarcerated status$/) do
  choose(IndividualMarket::ApplicantForm.radio_incarcerated, option: 'true')
end

And(/^user selects no for qhp applicant's indian_tribe_member status$/) do
  choose(IndividualMarket::ApplicantForm.indian_tribe_no, option: 'false')
end

And(/^user selects yes for qhp applicant's indian_tribe_member status$/) do
  choose(IndividualMarket::ApplicantForm.indian_tribe_yes, option: 'true')
  select 'ME', from: IndividualMarket::ApplicantForm.indian_tribe_state
  check(IndividualMarket::ApplicantForm.indian_tribe_other_code) if page.has_field?(IndividualMarket::ApplicantForm.indian_tribe_other_code)
  fill_in IndividualMarket::ApplicantForm.indian_tribe_other_name, with: 'Abenaki', wait: 5
end

And(/^user selects yes for qhp applicant's us_citizen status$/) do
  choose(IndividualMarket::ApplicantForm.us_citizen, option: 'true')
end

And(/^user selects no for qhp applicant's us_citizen status$/) do
  choose(IndividualMarket::ApplicantForm.us_citizen, option: 'false')
  checkboxes = all("[name=\"#{IndividualMarket::ApplicantForm.eligible_immigration_status}\"]")
  checkboxes.last.set(true) if checkboxes.any? # last is the 'no' option
end

And(/^user enters a valid state address for qhp (primary|dependent) applicant$/) do |role|
  if role == 'dependent'
    uncheck IndividualMarket::ApplicantForm.address_same_as_primary, allow_label_click: true, wait: 3
    fill_in IndividualMarket::ApplicantForm.address_line1, with: '123 Main St', wait: 1
    fill_in IndividualMarket::ApplicantForm.address_city, with: 'Casco'
  end

  if EnrollRegistry[:enroll_app].setting(:state_abbreviation).item == 'DC'
    select 'DC', from: IndividualMarket::ApplicantForm.address_state
    fill_in IndividualMarket::ApplicantForm.address_zip, with: '20001'
  else
    select 'ME', from: IndividualMarket::ApplicantForm.address_state
    fill_in IndividualMarket::ApplicantForm.address_zip, with: '04015'
  end
end

And(/^user enters an invalid state address for qhp (primary|dependent) applicant$/) do |role|
  if role == 'dependent'
    uncheck IndividualMarket::ApplicantForm.address_same_as_primary, allow_label_click: true, wait: 3
    fill_in IndividualMarket::ApplicantForm.address_line1, with: '123 Main St', wait: 1
    fill_in IndividualMarket::ApplicantForm.address_city, with: 'Denver'
  end

  select 'CO', from: IndividualMarket::ApplicantForm.address_state
  fill_in IndividualMarket::ApplicantForm.address_zip, with: '80014'
end

And(/^user selects no for qhp applicant's naturalized_citizen status$/) do
  choose(IndividualMarket::ApplicantForm.naturalized_citizen, option: 'false')
end

And(/user fills in the missing qhp relationship$/) do
  select 'Spouse', from: IndividualMarket::ApplicantForm.applicant_relationship
end

Then(/^the qhp applicant should have been created successfully$/) do
  step 'the user should see johnson in the dependent applicant first_name field'
  step 'the user should see smith in the dependent applicant last_name field'
end

When(/the user clicks the edit (primary|dependent) qhp applicant button$/) do |role|
  if role == 'primary'
    find(IndividualMarket::ApplicantForm.edit_primary_applicant).click
  else
    find(IndividualMarket::ApplicantForm.edit_dependent_button).click
  end
end

And(/^user clicks confirm member on the qhp application$/) do
  find(IndividualMarket::ApplicantForm.confirm_member_button).click
end

And(/^user clicks save changes on the qhp application$/) do
  find(IndividualMarket::ApplicantForm.save_changes_button).click
end

When(/^user completes the required fields in the qhp application$/) do
  steps %(
    And user enters qhp applicant name, ssn, gender and dob
    And user selects yes for qhp applicant's coverage requirement
    And user selects no for qhp applicant's incarcerated status
    And user selects no for qhp applicant's indian_tribe_member status
    And user selects yes for qhp applicant's us_citizen status
    And user selects no for qhp applicant's naturalized_citizen status
    And user fills in the missing relationship
    And user clicks confirm member on the qhp application
  )
end

When(/^more than one qhp member exists on the qhp application$/) do
  step 'user clicks the Add Member to Household button'
  step 'user completes the required fields in the qhp application'
end

When(/^user clicks on remove member from qhp application$/) do
  find(IndividualMarket::ApplicantForm.edit_dependent_button).click(wait: 5)
  find(IndividualMarket::ApplicantForm.remove_dependent_button).click(wait: 5)
  find(IndividualMarket::ApplicantForm.confirm_remove_dependent_button).click(wait: 5)
end

Then(/^the user should see the new member removed from the qhp application$/) do
  expect(page).not_to have_content('Member 2', wait: 5)
  expect(page).to have_content('Edit Member', count: 1)
end
