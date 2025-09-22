# frozen_string_literal: true

And(/user enters applicant name, ssn, gender and dob$/) do
  fill_in FinancialAssistance::ApplicantForm.applicant_first_name, :with => 'johnson'
  fill_in FinancialAssistance::ApplicantForm.applicant_last_name, :with => 'smith'
  fill_in FinancialAssistance::ApplicantForm.applicant_form_dob, :with => '10/10/1984'
  click_outside_datepicker(l10n('family_information'))
  fill_in FinancialAssistance::ApplicantForm.applicant_form_ssn, :with => '123456543'
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    select 'Male', from: FinancialAssistance::ApplicantForm.applicant_gender_select
  else
    find(:xpath, FinancialAssistance::ApplicantForm.applicant_form_gender_select_male).click
  end
end

And(/user enters applicant name, gender, dob and checks no ssn$/) do
  fill_in FinancialAssistance::ApplicantForm.applicant_first_name, :with => 'johnson'
  fill_in FinancialAssistance::ApplicantForm.applicant_last_name, :with => 'smith'
  fill_in FinancialAssistance::ApplicantForm.applicant_form_dob, :with => '10/10/1984'
  click_outside_datepicker(l10n('family_information'))
  check FinancialAssistance::ApplicantForm.applicant_form_no_ssn
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    select 'Male', from: FinancialAssistance::ApplicantForm.applicant_gender_select
  else
    find(:xpath, FinancialAssistance::ApplicantForm.applicant_form_gender_select_male).click
  end
end

And(/the user enters applicant information with us citizen false$/) do
  fill_in FinancialAssistance::ApplicantForm.applicant_first_name, :with => 'johnson'
  fill_in FinancialAssistance::ApplicantForm.applicant_last_name, :with => 'smith'
  fill_in FinancialAssistance::ApplicantForm.applicant_form_dob, :with => '10/10/1984'
  click_outside_datepicker(l10n('family_information'))
  check FinancialAssistance::ApplicantForm.applicant_form_no_ssn
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    select 'Male', from: FinancialAssistance::ApplicantForm.applicant_gender_select
    select 'Child', from: FinancialAssistance::ApplicantForm.applicant_relationship
    choose(FinancialAssistance::ApplicantForm.us_citizen, option: 'false')
    choose(FinancialAssistance::ApplicantForm.indian_tribe_member, option: 'false')
    choose(FinancialAssistance::ApplicantForm.radio_incarcerated, option: 'false')
  else
    find(:xpath, FinancialAssistance::ApplicantForm.applicant_form_gender_select_male).click
    find(:xpath, FinancialAssistance::ApplicantForm.applicant_spouse_select).click
    choose('indian_tribe_member_no', allow_label_click: true)
    choose('radio_incarcerated_no', allow_label_click: true)
  end
end

And(/a consumer with (.*) status exists$/) do |status|
  case status
  when 'immigration'
    application = FinancialAssistance::Application.first
    if application.present?
      applicant = application.primary_applicant
      applicant.update_attributes!(citizen_status: 'alien_lawfully_present', vlp_subject: 'Naturalization Certificate')
    else
      person = Person.all.first
      person.consumer_role.lawful_presence_determination.update_attributes!(
        vlp_document_type: 'Naturalization Certificate',
        vlp_document_number: '123456789',
        vlp_document_issue_date: Date.new(2010, 1, 1),
        vlp_document_expiration_date: Date.new(2025, 1, 1),
        citizen_status: 'alien_lawfully_present'
      )
    end
  when 'tribe'
    application = FinancialAssistance::Application.first
    if application.present?
      applicant = application.primary_applicant
      applicant.update_attributes!(citizen_status: 'us_citizen', indian_tribe_member: true, tribal_state: 'ME', tribe_codes: ['HM'])
    else
      person = Person.all.first
      person.update_attributes!(
        indian_tribe_member: true,
        tribal_name: 'Test Tribe',
        tribal_state: 'ME',
        tribe_codes: ["HM"],
        tribal_id: '123456789'
      )
    end
  end
end

And(/the user edits the primary applicant$/) do
  find("#edit-primary-applicant").click
end

Then(/fields related to the (.*) vlp document should display$/) do |type|
  case type
  when 'consumer'
    expect(page).to have_selector("#vlp_documents_container")
  when 'applicant'
    expect(page).to have_selector("#immigration_naturalization_cert_container")
  end
end

Then(/fields related to the consumer tribal status should display$/) do
  expect(page).to have_selector(".tribal-container")
end

And(/the consumer only has one mobile phone number$/) do
  person = Person.all.first
  person.phones.where(kind: 'home').destroy_all
  person.phones.create(kind: 'mobile', full_phone_number: '123-456-7890')
end

And(/user selects yes for applicant's coverage requirement$/) do
  find(:xpath, FinancialAssistance::ApplicantForm.is_applying_coverage_true).click
end

And(/user selects no for applicant's incarcerated status$/) do
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    choose(FinancialAssistance::ApplicantForm.radio_incarcerated, option: 'false')
  else
    choose('radio_incarcerated_no', allow_label_click: true)
  end
end

And(/user selects no for applicant's indian_tribe_member status$/) do
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    choose(FinancialAssistance::ApplicantForm.indian_tribe_member, option: 'false')
  else
    choose('indian_tribe_member_no', allow_label_click: true)
  end
end

And(/(.*) selects (.*) for applicant's us_citizen status$/) do |_, attestation|
  did_attest = attestation.downcase == 'yes'
  attestation_value = did_attest.to_s
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    choose(FinancialAssistance::ApplicantForm.us_citizen, option: attestation_value)
  else
    choose("applicant_us_citizen_#{attestation_value}", allow_label_click: true)
  end
end

And(/(.*) selects (.*) for applicant's eligibile immigration status$/) do |_, attestation|
  did_attest = attestation.downcase == 'yes'
  attestation_value = did_attest.to_s
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    choose(FinancialAssistance::ApplicantForm.eligible_immigration_status, option: attestation_value)
  else
    choose("applicant_eligible_immigration_status_#{attestation_value}", allow_label_click: true)
  end
end

And(/(.*) selects (.*) for applicant's naturalized_citizen status$/) do |_, attestation|
  did_attest = attestation.downcase == 'yes'
  attestation_value = did_attest.to_s
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    choose(FinancialAssistance::ApplicantForm.naturalized_citizen, option: attestation_value)
  else
    choose("applicant_naturalized_citizen_#{attestation_value}", allow_label_click: true)
  end
end

And(/(.*) selects (.*) immigration document option/) do |_, document_type|
  select document_type, from: FinancialAssistance::ApplicantForm.immigration_doc_type
end

And(/(.*) selects (.*) naturalization document option/) do |_, document_type|
  select document_type, from: FinancialAssistance::ApplicantForm.naturalization_doc_type
end

Then(/(.*) (should|should not) see the pre-1957 alien number warning/) do |_, can_see|
  if can_see == 'should'
    expect(page).to have_content("Pre-1956 certificates do not have an alien number. In this case, enter 9 nines (999999999)")
  else
    expect(page).to have_no_content("Pre-1956 certificates do not have an alien number. In this case, enter 9 nines (999999999)")
  end
end

And(/the user clicks the confirm member button$/) do
  find(EnrollRegistry.feature_enabled?(:bs4_consumer_flow) ? '#confirm-dependent' : ".btn.applicant-confirm-member").click
end

And(/user fills in the missing relationship$/) do
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    select 'Spouse', from: FinancialAssistance::ApplicantForm.applicant_relationship
  else
    find(:xpath, FinancialAssistance::ApplicantForm.applicant_spouse_select).click
  end
end

Then(/form should not submit due to required relationship options popup$/) do
  find(:xpath, "//div[@class='selectric-scroll']")
end

Then(/qhp applicant form should not create a new applicant due to required relationship$/) do
  url_application_id = page.current_url.match(%r{applications/([^/]+)})[1]
  qhp_app = IndividualMarket::Application.find(url_application_id)
  expect(qhp_app.applicants.count).to eq 1
end

Given(/the user has a dependent$/) do
  steps %(
    And user clicks the Add Member button
    And user enters applicant name, ssn, gender and dob
    And user selects yes for applicant's coverage requirement
    And user selects no for applicant's incarcerated status
    And user selects no for applicant's indian_tribe_member status
    And user selects yes for applicant's us_citizen status
    And user selects no for applicant's naturalized_citizen status
    And user fills in the missing relationship
    And the user clicks the confirm member button
  )
end

Given(/the user has a dependent with no ssn$/) do
  steps %(
    And user clicks the Add Member button
    And user enters applicant name, gender, dob and checks no ssn
    And user selects yes for applicant's coverage requirement
    And user selects no for applicant's incarcerated status
    And user selects no for applicant's indian_tribe_member status
    And user selects yes for applicant's us_citizen status
    And user selects no for applicant's naturalized_citizen status
    And user fills in the missing relationship
    And the user clicks the confirm member button
  )
end

Then(/the user should see disabled dob field for the applicant/) do
  [:applicant_form_dob].each do |selector|
    element = find("input[name=\"#{FinancialAssistance::ApplicantForm.send(selector)}\"]", visible: :all)
    expect(element[:readonly]).to eq "true"
  end
end

Then(/the user should see ssn editable & dob field disabled for the applicant/) do
  [:applicant_form_ssn, :applicant_form_dob].each do |selector|
    element = find("input[name=\"#{FinancialAssistance::ApplicantForm.send(selector)}\"]", visible: :all)
    if selector == :applicant_form_dob
      expect(element[:readonly]).to eq "true"
    else
      expect(element[:disabled]).to eq "false"
    end
  end
end

And(/user unchecks lives with primary subscriber$/) do
  checkbox = find('#applicant_same_with_primary')
  checkbox.set(false) if checkbox.checked?
  expect(page).to have_css('#applicant-home-address-area:not(.hidden)', visible: true)
end

And(/user fills in home address if needed$/) do
  within '#applicant-home-address-area' do
    fill_in 'applicant[addresses_attributes][0][address_1]', with: '123 Test Street'
    fill_in 'applicant[addresses_attributes][0][city]', with: 'Test City'
    select 'ME', from: 'applicant_addresses_attributes_0_state'
    fill_in 'applicant[addresses_attributes][0][zip]', with: '04001'
  end
end

Given(/the user has a dependent with no ssn and modal handling$/) do
  steps %(
    And user clicks the Add Member button
    And user enters applicant name, gender, dob and checks no ssn
    And user selects yes for applicant's coverage requirement
    And user selects no for applicant's incarcerated status
    And user selects no for applicant's indian_tribe_member status
    And user selects yes for applicant's us_citizen status
    And user selects no for applicant's naturalized_citizen status
    And user fills in the missing relationship
    And user unchecks lives with primary subscriber
    And user fills in home address if needed
  )
end

When(/user clicks confirm member and handles modal$/) do
  confirm_button = find(EnrollRegistry.feature_enabled?(:bs4_consumer_flow) ? '#confirm-dependent' : ".btn.applicant-confirm-member")
  confirm_button.click

  expect(page).to have_css('#addressChangeConfirmation', visible: true)

  within '#addressChangeConfirmation' do
    find('.close').click
  end

  expect(page).not_to have_css('#addressChangeConfirmation', visible: true)
end

Then(/the confirm member button should be re-enabled$/) do
  confirm_button = find(EnrollRegistry.feature_enabled?(:bs4_consumer_flow) ? '#confirm-dependent' : ".btn.applicant-confirm-member")

  expect(confirm_button).to be_visible
  expect(confirm_button).to be_present

  expect(confirm_button[:disabled]).not_to eq("true")
  expect(confirm_button[:disabled]).not_to eq(true)
end

When(/user clicks confirm member and accepts modal$/) do
  confirm_button = find(EnrollRegistry.feature_enabled?(:bs4_consumer_flow) ? '#confirm-dependent' : ".btn.applicant-confirm-member")
  confirm_button.click
  expect(page).to have_css('#addressChangeConfirmation', visible: true)

  within '#addressChangeConfirmation' do
    find('.btn-confirmation, .address-change-confirmation').click
  end

  expect(page).not_to have_css('#addressChangeConfirmation', visible: true)
end

Then(/the confirm member button should remain disabled$/) do
  confirm_button = find(EnrollRegistry.feature_enabled?(:bs4_consumer_flow) ? '#confirm-dependent' : ".btn.applicant-confirm-member")
  button_has_disabled_class = confirm_button[:class].include?('disabled')
  button_disabled_attr = confirm_button['disabled'] == 'disabled' || confirm_button['disabled'] == 'true'
  expect(button_has_disabled_class || button_disabled_attr).to be_truthy
end
