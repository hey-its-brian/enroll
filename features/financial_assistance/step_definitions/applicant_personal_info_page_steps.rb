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

And(/user selects no for applicant's coverage requirement$/) do
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

And(/user selects yes for applicant's us_citizen status$/) do
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    choose(FinancialAssistance::ApplicantForm.us_citizen, option: 'true')
  else
    choose('applicant_us_citizen_true', allow_label_click: true)
  end
end

And(/user selects no for applicant's naturalized_citizen status$/) do
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    choose(FinancialAssistance::ApplicantForm.naturalized_citizen, option: 'false')
  else
    choose('applicant_naturalized_citizen_false', allow_label_click: true)
  end
end

And(/user clicks comfirm member$/) do
  find(EnrollRegistry.feature_enabled?(:bs4_consumer_flow) ? '#confirm-dependent' : ".btn.applicant-confirm-member").click
end

Then(/form should not submit due to required relationship options popup$/) do
  find(:xpath, "//div[@class='selectric-scroll']")
end

And(/user fills in the missing relationship$/) do
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    select 'Spouse', from: FinancialAssistance::ApplicantForm.applicant_relationship
  else
    find(:xpath, FinancialAssistance::ApplicantForm.applicant_spouse_select).click
  end
end

Given(/the user has a dependent$/) do
  steps %(
    And user clicks the Add Member button
    And user enters applicant name, ssn, gender and dob
    And user selects no for applicant's coverage requirement
    And user selects no for applicant's incarcerated status
    And user selects no for applicant's indian_tribe_member status
    And user selects yes for applicant's us_citizen status
    And user selects no for applicant's naturalized_citizen status
    And user fills in the missing relationship
    And user clicks comfirm member
  )
end

Given(/the user has a dependent with no ssn$/) do
  steps %(
    And user clicks the Add Member button
    And user enters applicant name, gender, dob and checks no ssn
    And user selects no for applicant's coverage requirement
    And user selects no for applicant's incarcerated status
    And user selects no for applicant's indian_tribe_member status
    And user selects yes for applicant's us_citizen status
    And user selects no for applicant's naturalized_citizen status
    And user fills in the missing relationship
    And user clicks comfirm member
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
