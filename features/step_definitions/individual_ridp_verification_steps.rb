Given(/^that the consumer has navigated to the AUTH & CONSENT page$/) do
	visit 'insured/consumer_role/ridp_agreement'
end

When(/^the consumer selects “I Disagree”$/) do
  find(IvlAuthorizationAndConsent.i_disagree_radiobtn).click
end

When(/^the consumer clicks CONTINUE$/) do
	click_link "Continue"
end

Then(/^the consumer will be directed to the DOCUMENT UPLOAD page$/) do
	expect(page).to have_content('Identity')
	expect(page).to have_content('Application')
end

Given(/^that the consumer has “Disagreed” to AUTH & CONSENT$/) do
  visit 'insured/consumer_role/ridp_agreement'
  find(IvlAuthorizationAndConsent.i_disagree_radiobtn).click
  click_link "Continue"
end

And(/^the consumer is on the DOCUMENT UPLOAD page$/) do
  expect(page).to have_content('Identity', wait: 10)
	expect(page).to have_content('Application')
end

And(/^Application verification is OUTSTANDING$/) do
	person = Person.all.first
  expect(person.consumer_role.application_validation).to eq('outstanding')
  expect(page).to have_content('Outstanding')
end

And(/^Identity verification is OUTSTANDING$/) do
	person = Person.all.first
	expect(person.consumer_role.identity_validation).to eq('outstanding')
	expect(page).to have_content('Outstanding')
end

Then(/^the CONTINUE button is functionally DISABLED$/) do
  if EnrollRegistry[:bs4_consumer_flow].enabled?
    expect(page).to have_selector('a.btn.disabled.interaction-click-control-continue-to-next-step#continue_button')
  else
    expect(['disabled', 'true', '']).to include(find('.interaction-click-control-continue')['disabled'])
  end
end

Then(/^visibly DISABLED$/) do
  if EnrollRegistry[:bs4_consumer_flow].enabled?
    expected_color = 'rgba(224, 222, 220, 1)'
    element = find('a.btn.disabled.interaction-click-control-continue-to-next-step#continue_button')
    background_color = element.native.style('background-color')
    expect(background_color).to eq(expected_color)
  else
    expect(['disabled', 'true', '']).to include(find('.interaction-click-control-continue')['disabled'])
  end
end

And(/^an uploaded application in REVIEW status is present$/) do
  doc_id  = "urn:openhbx:terms:v1:file_storage:s3:bucket:'id-verification'{#sample-key}"
  file_path = File.dirname(__FILE__)
  allow_any_instance_of(Insured::RidpDocumentsController).to receive(:file_path).and_return(file_path)
  allow(Aws::S3Storage).to receive(:save).with(file_path, 'id-verification').and_return(doc_id)
  #find('#upload_application').click
  find(IvlVerifyIdentity.upload_application_docs_btn).click
	within '#upload_application' do
		attach_file("file[]", "#{Rails.root}/lib/pdf_templates/blank.pdf", visible:false)
  end
  wait_for_ajax(2)
	expect(page).to have_content('File Saved')
	expect(page).to have_content('In Review')
	person = Person.all.first
	expect(person.consumer_role.application_validation).to eq('pending')
end

And(/^an uploaded identity verification in REVIEW status is present$/) do
  doc_id = "urn:openhbx:terms:v1:file_storage:s3:bucket:'id-verification'{#sample-key}"
  file_path = File.dirname(__FILE__)
  allow_any_instance_of(Insured::RidpDocumentsController).to receive(:file_path).and_return(file_path)
  allow(Aws::S3Storage).to receive(:save).with(file_path, 'id-verification').and_return(doc_id)
  find(IvlVerifyIdentity.upload_identity_docs_btn).click
  find(IvlVerifyIdentity.select_file_to_upload_btn).click
	within '#select_upload_identity' do
		attach_file("file[]", "#{Rails.root}/lib/pdf_templates/blank.pdf", visible:false)
  end
  wait_for_ajax(2)
	expect(page).to have_content('File Saved')
	expect(page).to have_content('In Review')
	person = Person.all.first
	expect(person.consumer_role.identity_validation).to eq('pending')
end

And(/^an uploaded application in VERIFIED status is present$/) do
  login_as hbx_admin
  visit exchanges_hbx_profiles_root_path
  find(AdminHomepage.families_dropdown, wait: 5).click
  find(AdminHomepage.identity_ver_btn, wait: 5).click
  sleep 2
  find('td.sorting_1 a[class^="interaction-click-control"]').click
  expect(page).to have_css('h4', text: l10n('application'), wait: 5)
  ridp_id = Person.first.id
  within('#Application', wait: 10) do
    find(".interaction-choice-control-v-action-#{ridp_id}-application-1").click
  end
  find('.interaction-choice-control-verification-reason-14').click
  find('.v-type-confirm-button').click
  # the below text is generated on the back-end, so we are not referencing it via l10n
  expect(page).to have_css('.alert-success', text: 'Application successfully verified.')
end

And(/^an uploaded Identity verification in VERIFIED status is present$/) do
  login_as hbx_admin
  visit exchanges_hbx_profiles_root_path
  find(AdminHomepage.families_dropdown, wait: 5).click
  find(AdminHomepage.identity_ver_btn, wait: 5).click
  find('td.sorting_1 a[class^="interaction-click-control"]').click
  expect(page).to have_content('Identity', wait: 5)
  identity_id = Person.first.id
  within('#Identity', wait: 10) do
    find(".interaction-choice-control-v-action-#{identity_id}-identity-1").click
  end
  find('.interaction-choice-control-verification-reason-1').click
  find('.v-type-confirm-button').click
  # the below text is generated on the back-end, so we are not referencing it via l10n
  expect(page).to have_css('.alert-success', text: 'Identity successfully verified.')
end

Then(/^the CONTINUE button is functionally ENABLED$/) do
  expect(page).to have_selector('a.btn.interaction-click-control-continue-to-next-step#continue_button')
end

Then(/^visibly ENABLED$/) do
  find('.interaction-click-control-continue-to-next-step').visible?
end

When(/^the Admin clicks “Continue” on the doc upload page$/) do
  login_as hbx_admin
  visit exchanges_hbx_profiles_root_path
  find(AdminHomepage.families_dropdown, wait: 5).click
  find('li', :text => 'Families', :class => 'tab-second', :wait => 10).click
  sleep 2
  find_all('td.sorting_1 a[class^="interaction-click-control"]')[0].click
end

Then(/^the Admin is unable to complete the application for the consumer until ID is verified$/) do
  if EnrollRegistry[:bs4_consumer_flow].enabled?
    expect(page).to have_selector('a.btn.disabled.interaction-click-control-continue-to-next-step#continue_button')
  else
    expect(['disabled', 'true', '']).to include(find('.interaction-click-control-continue')['disabled'])
  end
end


When(/^the consumer selects “I Agree”$/) do
  expect(page).to have_css('h1', text: l10n('insured.consumer_roles.ridp_agreement.heading'))
  find(IvlAuthorizationAndConsent.i_agree_radiobtn).click
  find(".interaction-click-control-continue-to-next-step").click
end

Then(/^the consumer will be directed to answer the Experian Identity Proofing questions$/) do
  expect(page).to have_content('Verify Identity')
  find(IvlVerifyIdentity.pick_answer_a).click
  find(IvlVerifyIdentity.pick_answer_c).click
end

And(/^that the consumer has answered the Experian Identity Proofing questions$/) do
  find(IvlVerifyIdentity.pick_answer_a).click
  find(IvlVerifyIdentity.pick_answer_c).click
  # screenshot("identify_verification")
  find('.interaction-click-control-submit').click
end

When(/^Experian is unable to verify Identity for the consumer$/) do
  expect(page).to have_content('Identity')
  expect(page).to have_content('Application')
end

When(/^an Experian Error screen appears for the consumer$/) do
  expect(page).to have_content('Experian, the third-party service we use to verify your identity, could not confirm your information.')
end

When(/^an uploaded Identity verification in VERIFIED status is present on failed experian screen$/) do
  login_as hbx_admin
  visit exchanges_hbx_profiles_root_path
  find(AdminHomepage.families_dropdown, wait: 5).click
  find(AdminHomepage.identity_ver_btn, wait: 5).click
  find('td.sorting_1 a[class^="interaction-click-control"]').click
  sleep 2
  expect(page).to have_content('Identity')
  expect(page).to have_css('h4', text: l10n('application'), wait: 5)
  ridp_id = Person.first.id
  within('#Application', wait: 10) do
    find(".interaction-choice-control-v-action-#{ridp_id}-application-1").click
  end
  find('.interaction-choice-control-verification-reason-14').click
  find('.v-type-confirm-button').click
  # the below text is generated on the back-end, so we are not referencing it via l10n
  expect(page).to have_css('.alert-success', text: 'Application successfully verified.')
end

When(/^an uploaded application in VERIFIED status is present on failed experian screen$/) do
  login_as hbx_admin
  visit exchanges_hbx_profiles_root_path
  find(AdminHomepage.families_dropdown, wait: 5).click
  find('.interaction-click-control-identity-verification', wait: 5).click
  find('td.sorting_1 a[class^="interaction-click-control"]').click
  sleep 2
  expect(page).to have_content('Application', wait: 5)
  expect(page).to have_css('h4', text: l10n('application'), wait: 5)
  ridp_id = Person.first.id
  within('#Application', wait: 10) do
    find(".interaction-choice-control-v-action-#{ridp_id}-application-1").click
  end
  find('.interaction-choice-control-verification-reason-14').click
  find('.v-type-confirm-button').click
  # the below text is generated on the back-end, so we are not referencing it via l10n
  expect(page).to have_css('.alert-success', text: 'Application successfully verified.')
end

Then(/^HBX admin should see the dependents form$/) do
  expect(page).to have_content('Add Member')
  # screenshot("dependents")
end

And(/^HBX admin click on continue button on household info form$/) do
  find_all(IvlIapFamilyInformation.continue_btn)[0].click
end

And(/^HBX admin clicks continue after approving Identity document$/) do
  find(IvlVerifyIdentity.continue_btn).click
  sleep 2
end

When(/^HBX admin click on none of the situations listed above apply checkbox$/) do
  expect(page).to have_content 'None of the situations listed above apply'
  find(IvlSpecialEnrollmentPeriod.none_apply_checkbox).click
  expect(page).to have_content 'To enroll before Open Enrollment'
end

And(/^HBX admin click on back to my account button$/) do
  expect(page).to have_content "To enroll before Open Enrollment, you must qualify for a Special Enrollment Period"
  find(IvlSpecialEnrollmentPeriod.outside_open_enrollment_back_to_my_account_btn).click
end

Then(/^HBX admin should land on home page$/) do
  if EnrollRegistry[:bs4_consumer_flow].enabled?
    expect(page).to have_css('h1', text: "My CoverME.gov")
  else
    expect(page).to have_content EnrollRegistry[:enroll_app].setting(:short_name).item
  end
end

And(/^I click on Continue button$/) do
  find(:xpath, "//*[@id='btn-continue']").click
end

