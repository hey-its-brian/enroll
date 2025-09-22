# frozen_string_literal: true

And(/the user updates the first_name of the (primary|dependent) qhp applicant to (.*?)$/) do |_role, value|
  fill_in IndividualMarket::ApplicantForm.applicant_first_name, with: value, wait: 10
end

And(/the user updates the last_name of the (primary|dependent) qhp applicant to (.*?)$/) do |_role, value|
  fill_in IndividualMarket::ApplicantForm.applicant_last_name, with: value, wait: 10
end

And(/the user updates the dob of the (primary|dependent) qhp applicant to (.*?)$/) do |_role, value|
  date = (DateTime.now - value.to_i.years).strftime('%d/%m/%Y')
  fill_in IndividualMarket::ApplicantForm.applicant_form_dob, :with => date, wait: 10
  click_outside_datepicker(l10n('family_information'))
end

And(/the user updates the gender of the (primary|dependent) qhp applicant to (.*?)$/) do |_role, value|
  select value.capitalize, from: IndividualMarket::ApplicantForm.applicant_gender_select
end

And(/the user updates the relationship of the dependent qhp applicant to (.*?)$/) do |value|
  humanized_value = value.tr('_', ' ').capitalize
  select humanized_value, from: IndividualMarket::ApplicantForm.applicant_relationship
end

Then(/^the user should see (.*?) in the (primary|dependent) applicant (first_name|last_name) field$/) do |value, role, _name_type|
  id = IndividualMarket::Application.last.non_primary_applicants.first.id
  field = role == 'primary' ? 'interaction-field-control-primary-name' : "interaction-field-control-dependent-#{id}-name"
  input = page.find("input.#{field}", visible: :all)
  expect(input.value).to include(value)
end

Then(/^the user should see (.*?) in the (primary|dependent) applicant dob field$/) do |value, role|
  today = DateTime.now
  dob = (today - value.to_i.years)
  age = today.year - dob.year
  age -= 1 if today < dob + age.years

  if role == 'primary'
    field = 'interaction-field-control-primary-age'
  else
    id = IndividualMarket::Application.last.non_primary_applicants.first.id
    field = "interaction-field-control-dependent-#{id}-age"
  end

  input = page.find("input.#{field}", visible: :all)
  expect(input.value).to_not include(age.to_s) # dob should be readonly
end

Then(/^the user should see (.*?) in the dependent applicant relationship field$/) do |value|
  humanized_value = value.tr('_', ' ').split.map(&:capitalize).join(' ')
  id = IndividualMarket::Application.last.non_primary_applicants.first.id
  field = "interaction-field-control-dependent-#{id}-relation"
  input = page.find("input.#{field}", visible: :all)
  expect(input.value).to include(humanized_value)
end

Then(/^the user should see (.*?) in the (primary|dependent) applicant gender field$/) do |value, role|
  humanized_value = value.capitalize
  id = IndividualMarket::Application.last.non_primary_applicants.first.id
  field = role == 'primary' ? 'interaction-field-control-primary-gender' : "interaction-field-control-dependent-#{id}-gender"
  input = page.find("input.#{field}", visible: :all)
  expect(input.value).to include(humanized_value)
end
