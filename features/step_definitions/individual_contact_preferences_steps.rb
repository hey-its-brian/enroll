# frozen_string_literal: true

# Form submission steps
When('the Individual submits the contact preferences form') do
  page.execute_script("document.querySelector('input[type*=\"submit\"]').click()")
end

# Data entry steps
Given('the Individual enters a mobile phone number') do
  find(IvlContactPreferences.mobile_phone_field).fill_in with: '555-123-4567'
end

Given('the Individual enters a home phone number') do
  find(IvlContactPreferences.home_phone_field).fill_in with: '555-123-4567'
end

Given('the Individual enters a personal email address') do
  find(IvlContactPreferences.personal_email_field).fill_in with: 'user@example.com'
end

Given('the Individual enters a mobile phone number with all zeros') do
  find(IvlContactPreferences.mobile_phone_field).fill_in with: '0000000000'
end

Given('the Individual enters a mobile phone number beginning with zero') do
  find(IvlContactPreferences.mobile_phone_field).fill_in with: '0123456789'
end

Given('the Individual enters a home phone number with all zeros') do
  find(IvlContactPreferences.home_phone_field).fill_in with: '0000000000'
end

Given('the Individual enters a home phone number beginning with zero') do
  find(IvlContactPreferences.home_phone_field).fill_in with: '0123456789'
end

Given('the Individual enters a short mobile phone number') do
  find(IvlContactPreferences.mobile_phone_field).fill_in with: '12345'
end

Given('the Individual enters a short home phone number') do
  find(IvlContactPreferences.home_phone_field).fill_in with: '12345'
end

# Contact method selection steps
When('the Individual clears the contact method checkboxes') do
  find(IvlContactPreferences.email_contact_method).uncheck
  find(IvlContactPreferences.mail_contact_method).uncheck
  find(IvlContactPreferences.text_contact_method).uncheck
end

When(/the Individual selects (.+) as contact method/) do |contact_option|
  method = case contact_option
           when 'text messaging'
             IvlContactPreferences.text_contact_method
           when 'email'
             IvlContactPreferences.email_contact_method
           when 'mail'
             IvlContactPreferences.mail_contact_method
           end
  find(method).check
end

When('the Individual unfocuses the current field') do
  page.execute_script("document.activeElement.blur()")
end

# Validation assertion steps
Then('the Individual should see a generic alert {string}') do |message|
  alert_text = accept_alert
  expect(alert_text).to eq(message)
end

Then('the Individual should see a validation message {string}') do |message|
  invalid_field = page.find('input:invalid')
  validation_message = page.evaluate_script("arguments[0].validationMessage", invalid_field)
  expect(validation_message).to eq(message)
end

Then('the continue button should remain enabled') do
  expect(page).to have_selector(IvlContactPreferences.continue_button)
  expect(page).not_to have_selector("#{IvlContactPreferences.continue_button}.disabled")
end

Then('the Individual should proceed to the next step') do
  expect(page).not_to have_content('Contact Preferences')
end

# Page load assertions
Then('the Individual should see the Contact Preferences title') do
  expect(page).to have_selector('h1', text: 'Contact Preferences')
end

Then('the Individual should see the contact explanation text') do
  expect(page).to have_content('Please provide us with your contact preferences. This will be used to assist the call center if you forget your password.')
  expect(page).to have_content('An email or mobile phone number is required. When you’re finished, select')
end

Then('the Individual should see the contact fields') do
  expect(page).to have_selector(IvlContactPreferences.home_phone_field)
  expect(page).to have_selector(IvlContactPreferences.mobile_phone_field)
  expect(page).to have_selector(IvlContactPreferences.personal_email_field)
  expect(page).to have_selector(IvlContactPreferences.work_email_field)
end

Then('the Individual should see the Notices subtitle') do
  expect(page).to have_selector('h2', text: 'Notices')
end

Then('the Individual should see the contact preferences fields') do
  expect(page).to have_selector(IvlContactPreferences.email_contact_method)
  expect(page).to have_selector(IvlContactPreferences.mail_contact_method)
  expect(page).to have_selector(IvlContactPreferences.text_contact_method)
end

Then('Email and Mail preferences should be checked') do
  expect(page).to have_selector("#{IvlContactPreferences.email_contact_method}:checked")
  expect(page).to have_selector("#{IvlContactPreferences.mail_contact_method}:checked")
end

Then('the Individual should see the language preferences field') do
  expect(page).to have_selector(IvlContactPreferences.language_preference_dropdown)
end

Then('the Individual should see the continue button') do
  expect(page).to have_selector(IvlContactPreferences.continue_button)
  expect(page).not_to have_selector("#{IvlContactPreferences.continue_button}.disabled")
end

# Required assertions
Then(/the (home email|mobile phone) field should( not)? be marked as required/) do |field_type, negation|
  field_selector = case field_type
                   when 'home email'
                     IvlContactPreferences.personal_email_field
                   when 'mobile phone'
                     IvlContactPreferences.mobile_phone_field
                   end

  field = find(field_selector)
  field_id = field[:id]
  label = find("label[for='#{field_id}']")

  if negation
    expect(label[:class]).not_to include('required')
  else
    expect(label[:class]).to include('required')
  end
end
