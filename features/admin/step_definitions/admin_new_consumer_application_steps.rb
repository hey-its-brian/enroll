Given(/^Hbx Admin is on ridp document upload page$/) do
  visit '/insured/consumer_role/upload_ridp_document'
end

When(/^hbx admin uploads application document and verifies application$/) do
  doc_id  = "urn:openhbx:terms:v1:file_storage:s3:bucket:'id-verification'{#sample-key}"
  file_path = File.dirname(__FILE__)
  allow_any_instance_of(Insured::RidpDocumentsController).to receive(:file_path).and_return(file_path)
  allow(Aws::S3Storage).to receive(:save).with(file_path, 'id-verification').and_return(doc_id)
  find('#upload_application').click
  within '#upload_application' do
    attach_file("file[]", "#{Rails.root}/lib/pdf_templates/blank.pdf", visible:false)
  end
  wait_for_ajax(2)
  expect(page).to have_content('File Saved')
  expect(page).to have_content('In Review')
  within('#Application') do
    find('.label', :text => 'Action').click
    find('li', :text => 'Verify').click
  end

  find('.verification-update-reason').click
  find('li', :text => 'Document in EnrollApp').click
  find('.v-type-confirm-button').click

  expect(page).to have_content('Application successfully verified.')
end

Then(/^Hbx admin visits household info page$/) do
  expect(page).to have_content('Family Information')
end

Then(/^Admin continues to families home page$/) do
  visit 'families/home'
end

When(/^user registers as an individual$/) do
  fill_in IvlPersonalInformation.first_name, with: "Patrick"
  fill_in IvlPersonalInformation.last_name, with: "Doe"
  fill_in IvlPersonalInformation.dob, with: "11/11/1991"
  fill_in IvlPersonalInformation.ssn, with: '212-31-3131'
  find(IvlPersonalInformation.male_radiobtn).click
  find(IvlPersonalInformation.need_coverage_yes).click
  find(IvlPersonalInformation.continue_btn).click
end

When(/^user registers as an individual female gender$/) do
  fill_in IvlPersonalInformation.first_name, with: "John"
  fill_in IvlPersonalInformation.last_name, with: "Smith"
  fill_in IvlPersonalInformation.dob, with: "11/11/1991"
  fill_in IvlPersonalInformation.ssn, with: '212-31-3131'
  find(IvlPersonalInformation.female_radiobtn).click
  find(IvlPersonalInformation.need_coverage_yes).click
  find(IvlPersonalInformation.continue_btn).click
end

When(/^the Individual selects “I Disagree”$/) do
  find(:xpath, '//label[@for="agreement_disagree"]').click
end

When(/^the Individual clicks CONTINUE$/) do
  click_link "Continue"
end

Then(/^Individual should land on Documents upload page$/) do
  expect(page).to have_content('Verified')
  expect(page).to have_content('Identity')
  expect(page).to have_content('Application')
end

When(/^clicks on Individual in Families tab$/) do
  login_as hbx_admin
  visit exchanges_hbx_profiles_root_path
  find(:xpath, "//li[contains(., '#{"Families"}')]", :wait => 10).click
  find('li', :text => 'Families', :class => 'tab-second', :wait => 10).click
  find('a', :text => /\AJohn Smith\z/, :wait => 10).click
  expect(page).to have_content('Identity')
end

Then(/^Admin should land on ridp document upload page$/) do
  expect(page).to have_content('Identity')
end

When(/^admin navigates to .+ user who has (.*) to American Indian or Alaska Native tribe membership$/) do |attest|
  @person = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, first_name: "Patrick")
  @family = FactoryBot.create(:family, :with_primary_family_member, person: @person)
  FactoryBot.create(:user, person: @person)

  case attest
  when 'attested'
    @person.update_attributes!(tribal_id: '123456789', tribal_name: 'Navajo', tribal_state: 'ME')
    @person.verification_types.create!(type_name: 'American Indian Status', validation_status: 'verified')
  when 'not attested'
    @person.update_attributes!(tribal_id: nil)
  else
    raise 'Step only accepts "attested" or "not_attested" for attestation'
  end

  visit family_index_dt_exchanges_hbx_profiles_path
  find('[class^="interaction-click-control-patrick-smith"]').click
end

And(/^FAA application exists in determined state$/) do
  FactoryBot.create(:financial_assistance_application, family_id: @family.id, aasm_state: 'determined')
  FactoryBot.create(
    :financial_assistance_applicant,
    application: application,
    is_primary_applicant: true,
    family_member_id: @person.id,
    person_hbx_id: @person.hbx_id
  )
end

And(/^.+ navigates to the user's (.*) page$/) do |tab|
  sleep 2
  case tab
  when 'documents'
    find('.interaction-click-control-verifications').click
  when 'applications'
    if ENV['CLIENT'] == 'me'
      find('[class$="applications"]').click
    else
      find('.interaction-click-control-cost-savings').click
    end
  when 'families'
    find('.interaction-click-control-my-household').click
  else
    raise 'Step only accepts navigation tab names as tab'
  end
end

And(/^.+ updates the (.*)'s American Indian or Alaska Native attestation$/) do |user|
  case user
  when 'user'
    find('.interaction-click-control-edit-member').click
    find('#indian_tribe_member_yes').click
    find('#tribal-id').set('123456789')
    find('#save_personal').click
  when 'dependent'
    find('#indian_tribe_member_yes').click
    find('#tribal-id').set('123456789')
    find('#confirm-dependent').click
  else
    raise 'Step only accepts user or dependent'
  end
end

And(/^.+ adds a dependent to the user's family$/) do
  find('#household_info_add_member').click
  find('#applicant_first_name').set('Cathy')
  find('#applicant_last_name').set('Smith3')
  find('#applicant_dob').set('10/10/1984')
  find('#applicant_gender').set('Female')
  options_gender = find('#applicant_gender').all('option')
  options_gender[2].select_option
  find('#dependent_ssn').set('123456543')
  options_relationship = find('#applicant_relationship').all('option')
  options_relationship[1].select_option
  find('#us_citizen_true').click
  find('#naturalized_citizen_false').click
  find('#is_incarcerated_false').click
end

And(/^admin accesses the user's financial assistance application$/) do
  first('.interaction-click-control-actions').click
  find('.interaction-click-control-copy-to-new-application').click
end

And(/^.+ clicks on the Actions dropdown for the American Indian Status$/) do
  first('select[id^="v-action"][id*="American-Indian-Status"]').click
end

Then(/^.+ should see only View History action available$/) do
  select_element = first('select[id^="v-action"][id*="American-Indian-Status"]')
  expect(select_element).to have_selector('option', count: 2)
  options = select_element.all('option')
  expect(options[1].value).to eq('View History')
end

And(/^.+ returns to the applications page$/) do
  sleep 2
  visit '/financial_assistance/applications?tab=cost_savings'
end
