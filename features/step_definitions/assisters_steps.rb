# frozen_string_literal: true

module AssisterStepsHelper
  include Config::AcaHelper
end

World(AssisterStepsHelper)

When(/^.+ visits the HBX Assister Registration form$/) do
  visit '/'
  find(".assister-registration", wait: 10).click
end

When(/^Primary Assister should see the New Assister Agency form$/) do
  find('#assister_registration_form', wait: 20)
  expect(page).to have_css("#assister_registration_form")
  # Agency fields are part of the assister registration form
  expect(page).to have_content("Assister Agency Information")
end

And(/^.+ enters assister agency information for individual markets$/) do
  fill_in 'organization[legal_name]', with: "Logistics Inc"
  fill_in 'organization[dba]', with: "Logistics Inc"
  # Auto-Generates FEIN
  # fill_in 'organization[fein]', with: "890890891"

  # this field was hidden 4/13/2016
  # find(:xpath, "//p[@class='label'][contains(., 'Select Entity Kind')]").click
  # find(:xpath, "//li[contains(., 'C Corporation')]").click

  find(:xpath, "//p[@class='label'][contains(., 'Select Practice Area')]").click
  find(:xpath, "//li[contains(., 'Both - Individual & Family AND Small Business Marketplaces')]").click

  find('button.multiselect').click
  find(:xpath, '//label[input[@value="bn"]]').click
  find(:xpath, '//label[input[@value="fr"]]').click

  find(:xpath, "//label[input[@name='organization[accept_new_clients]']]").click
  find(:xpath, "//label[input[@name='organization[working_hours]']]").click
end

And(/^Current assister agency is fake fein$/) do
  assister_agency.is_fake_fein = true
  assister_agency.save
end

And(/^.+ enters assister agency information for SHOP markets$/) do
  fill_in 'agency[organization][legal_name]', with: "Logistics Inc"
  fill_in 'agency[organization][dba]', with: "Logistics Inc"
  # fill_in 'agency[organization][fein]', with: "890890891"
  # Auto-Generates FEIN
  # fill_in 'organization[fein]', with: "890890891"

  # this field was hidden 4/13/2016
  # find(:xpath, "//p[@class='label'][contains(., 'Select Entity Kind')]").click
  # find(:xpath, "//li[contains(., 'C Corporation')]").click

  # find(:xpath, "//p[@class='label'][contains(., 'Select Practice Area')]").click
  # find(:xpath, "//li[contains(., 'Small Business Marketplace ONLY')]").click
  select 'Small Business Marketplace ONLY', from: "agency_organization_profile_attributes_market_kind"
  # Languages
  find("option[value='tr']").click
  find("#agency_organization_profile_attributes_accept_new_clients").click

  if aca_assister_routing_information
    fill_in 'agency_organization_profile_attributes_ach_routing_number', with: '123456789'
    fill_in 'agency_organization_profile_attributes_ach_routing_number_confirmation', with: '123456789'
    fill_in 'agency_organization_profile_attributes_ach_account_number', with: '9999999999999999'
  end
  # Using this as a seperate step was deleting the rest of the form
  role = "Primary Assister"
  location = 'default_office_location'
  location = eval(location) if location.instance_of?(String) # rubocop:disable Security/Eval
  RatingArea.where(zip_code: "01001").first || FactoryBot.create(:rating_area, zip_code: "01001", county_name: "Hampden", rating_area: Settings.aca.rating_areas.first)
  fill_in 'agency[organization][profile_attributes][office_locations_attributes][0][address_attributes][address_1]', :with => location[:address1]
  fill_in 'agency[organization][profile_attributes][office_locations_attributes][0][address_attributes][address_2]', :with => location[:address2]
  fill_in 'agency[organization][profile_attributes][office_locations_attributes][0][address_attributes][city]', :with => location[:city]
  select "DC", from: "inputState"
  # agency[organization][profile_attributes][office_locations_attributes][0][address_attributes][state]
  # find(:xpath, "//div[contains(@class, 'selectric-scroll')]/ul/li[contains(text(), '#{location[:state]}')]").click

  fill_in 'agency[organization][profile_attributes][office_locations_attributes][0][address_attributes][zip]', :with => location[:zip]
  if role.include? 'Employer'
    wait_for_ajax
    select (location[:county]).to_s, :from => "agency[organization][profile_attributes][office_locations_attributes][0][address_attributes][county]"
  end
  fill_in 'agency[organization][profile_attributes][office_locations_attributes][0][phone_attributes][area_code]', :with => location[:phone_area_code]
  fill_in 'agency[organization][profile_attributes][office_locations_attributes][0][phone_attributes][number]', :with => location[:phone_number]
  wait_for_ajax
  # Clicking the 'Create Assister Agency' button
  find("#assister-btn").click
end


And(/^.+ clicks? on Create Assister Agency$/) do
  wait_for_ajax
  page.find('h1', text: 'Assister Registration').click
  wait_for_ajax
  # Clicking the 'Create Assister Agency' button
  find("#assister-btn").click
end

Then(/^.+ should see assister registration successful message$/) do
  expect(page).to have_content("Complete the following requirements to become a #{EnrollRegistry[:enroll_app].setting(:short_name).item} Registered Assister") if assister_approval_period_enabled?
  expect(page).to have_content('Your registration has been submitted. A response will be sent to the email address you provided once your application is reviewed.')
end

Then(/^.+ should see assister npn validation error message$/) do
  expect(page).to have_content('Please provide a NPN.')
end

def assister_approval_period_enabled?
  EnrollRegistry.feature_enabled?(:assister_approval_period)
end

# And(/^.+ should see the list of assister applicants$/) do
# end

Then(/^.+ click the current assister applicant show button$/) do
  find('.interaction-click-control-assister-show').click
end

And(/^.+ should see the assister application with carrier appointments$/) do
  if Settings.aca.assister_carrier_appointments_enabled
    find_all("[id^=person_assister_role_attributes_carrier_appointments_]").each do |checkbox|
      checkbox.should be_checked
    end
    expect(page).to have_text(l10n("assister_carrier_appointments_enabled_note", site_long_name: site_long_name))
  end
end

And(/^.+ click approve assister button$/) do
  find('.interaction-click-control-assister-approve').click
end

Then(/^.+ should see the assister successfully approved message$/) do
  expect(page).to have_content('Assister applicant approved successfully.')
end

When(/^(.*?) go[es]+ to the assisters tab$/) do |legal_name|
  profile = @organization[legal_name].employer_profile
  visit benefit_sponsors.profiles_employers_employer_profile_path(profile.id, :tab => 'assisters')
  sleep 15
end

Then(/^.+ should see successful message with assister agency home page$/) do
  welcome_text = HomePage.agency_home_page_welcome_text
  expect(page).to have_content(welcome_text)

  current_assister_legal_name = Person.all.detect(&:assister_role).assister_role.assister_agency_profile.legal_name
  expect(page).to have_content("Agency : #{current_assister_legal_name}")
end

Then(/^.+ should see no active assister$/) do
  expect(page).to have_content('You have no active Assister')
end

When(/^.+ clicks? on Browse Assisters button$/) do
  find('.interaction-click-control-browse-assisters').click
end

Then(/^.+ should see assister agencies index view$/) do
  @assister_agency_profiles.each_key do |assister_agency_name|
    element = find("div#assister_agencies_listing a", text: /#{assister_agency_name}/i, wait: 5)
    expect(element).to be_present
  end
end

When(/^.+ searches assister agency (.*?)$/) do |legal_name|
  find('.assister_agencies_search')
  fill_in 'q', with: (legal_name || assister_agency_profile.legal_name)
  find('.search-wp .btn').click
end

When(/^.+ searches primary assister (.*?)$/) do |assister_name|
  find('.assister_agencies_search')
  fill_in 'q', with: assister_name
  find('.search-wp .btn').click
end

Then(/^.+ should see assister agency (.*?)$/) do |legal_name|
  element = find("div#assister_agencies_listing a", text: /#{legal_name || assister_agency_profile.legal_name}/i, wait: 5)
  expect(element).to be_present
end

Then(/^.+ clicks? select assister button$/) do
  click_link 'Select Assister'
end

Then(/^.+ confirms? assister selection$/) do
  within '.modal-dialog' do
    find('input.btn-primary').click
  end
end

Then(/^.+ should see assister selected successful message$/) do
  wait_for_ajax(1,0.5)
  expect(page).to have_content("Your assister has been notified of your selection and should contact you shortly. You can always call or email them directly. If this is not the assister you want to use, select 'Change Assister'.")
end

And(/^.+ should see assister (.*?) and agency (.*?) active for the employer$/) do |assister_name, agency_name|
  find('#active_assister_tab #employer-assister-card', text: /Active Assister/i, wait: 5)
  expect(page).to have_content(/#{assister_name}/i)
  expect(page).to have_content(/#{agency_name}/i)
end

When(/^.+ terminates assister$/) do
  find('.interaction-click-control-change-assister').click
  find('.modal-title', text: 'Assister Termination Confirmation', wait: 5)
  within '.modal-dialog' do
    click_link 'Terminate Assister'
  end
end

Then(/^.+ should see assister terminated message$/) do
  expect(page).to have_content('Assister terminated successfully.')
end

Then(/^.+ should see the Employer (.*?) page as Assister$/) do |_legal_name|
  expect(page).to have_content(employer.legal_name)
  expect(page).to have_content("I'm a Assister")
end

When(/^Primary Assister publishes the benefit application$/) do
  find('.interaction-click-control-publish-plan-year').click
end

Then(/assister (.*?) should receive application (.*?) notification$/) do |assister_name, notification_kind|
  assister_email_address = @assisters[assister_name]&.email_address
  subject =
    case notification_kind
    when 'denial'
      'Assister application denied'
    when 'approval'
      "Invitation to create your Assister account on #{site_short_name}"
    when 'extended'
      "Action Needed - Complete Assister Training for #{site_short_name}"
    end
  open_email(
    assister_email_address,
    :with_subject => subject
  )
  expect(current_email.to).to eq([assister_email_address])
end

Then(/^.+ should see assister (.*?) under extended tab$/) do |assister_name|
  expect(page).to have_content(assister_name)
end

Then(/^.+ should see on the page assister (.*?)$/) do |assister_name|
  expect(page).to have_content(assister_name)
end

Then(/^.+ should not see on the page assister (.*?)$/) do |assister_name|
  expect(page).not_to have_content(assister_name)
end

When(/^.+ click deny assister button$/) do
  find('.interaction-click-control-assister-deny').click
end

When(/^.+ click extend assister button$/) do
  find('.interaction-click-control-assister-extend').click
end

Then(/^.+ should see the assister application denied message$/) do
  expect(page).to have_content('Assister applicant denied.')
end

Then(/^.+ should see the assister application extended message$/) do
  expect(page).to have_content('Assister applicant is now extended.')
end

Then(/Primary Assister should see Employer and click on legal name$/) do
  click_link(employer.legal_name)
end

Then(/Primary Assister clicks on shop for plans$/) do
  allow_any_instance_of(Insured::GroupSelectionController).to receive(:is_user_authorized?).and_return(true)
  find('.interaction-click-control-shop-for-plans').click
  find("#btn-continue").click
end

Then(/Primary Assister clicks on confirm Confirm button on the coverage summary page$/) do
  find(EmployeeConfirmYourPlanSelection.confirm_btn).click
end

Then(/Primary Assister sees Enrollment Submitted and clicks Continue$/) do
  find(EmployeeEnrollmentSubmitted.continue_btn).click
end

Then(/Primary Assister should see Coverage Selected$/) do
  expect(page).to have_content('Coverage Selected')
end
