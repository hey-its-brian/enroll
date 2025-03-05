module VerificationUser
  def user(*traits)
    attributes = traits.extract_options!
    @user ||= FactoryBot.create :user, *traits, attributes
  end
end
World(VerificationUser)

Then(/^Individual click continue button$/) do
  find('.btn', text: 'CONTINUE').click
end

Then(/^I should see Documents link$/) do
  expect(page).to have_content "Documents"
end

When(/^.+ clicks on Documents link$/) do
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    find(IvlHomepage.verifications_link, wait: 5).click
  else
    find('.interaction-click-control-documents').click
  end
end

And(/^.+ clicks on Verification History$/) do
  find(IvlDocumentDetail.verification_history_link).click
end

And(/^.+ lands in the Verifications page$/) do
  if EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)
    expect(page).to have_content "Verifications"
  else
    expect(page).to have_content "Documents"
  end
end

And(/the determination for the family has been built/) do
  ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: user.person.primary_family.reload, effective_date: TimeKeeper.date_of_record)
end

And(/^.+ clicks on member with verified status$/) do
  find_all(IvlDocumentsPage.member_link).first.click
end

Given(/^I should see page for documents verification$/) do
  expect(page).to have_content "Documents We Accept"
  expect(page).to have_content('Social Security Number')
  find('.btn', text: 'Documents We Accept').click
  expect(page).to have_content('DC Residency')
  link = find_link('https://dmv.dc.gov/page/proof-dc-residency-certifications')
  link.visible?
  expect(link[:target]).to eq('_blank')
  expect(link[:rel]).to eq('noopener noreferrer')
  new_window = window_opened_by { click_link 'https://dmv.dc.gov/page/proof-dc-residency-certifications' }
  switch_to_window new_window
end

Given(/^a consumer exists$/) do
  user :with_consumer_role
end

Given(/^the consumer is logged in$/) do
  login_as user
end

And(/^the user is RIDP verified$/) do
  user.person.consumer_role.move_identity_documents_to_verified
end

Given(/the consumer has a verification with (\w+) status/) do |status|
  FactoryBot.create(:verification_type, type_name: "Citizenship", validation_status: status, update_reason: "Mock Reason", due_date: TimeKeeper.date_of_record, person: user.person)
  ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: user.person.primary_family.reload, effective_date: TimeKeeper.date_of_record)
end

Given(/the alive_status feature is enabled/) do
  allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)
end

Given(/the show_new_documents_tab_text feature is enabled/) do
  allow(EnrollRegistry[:show_new_documents_tab_text].feature).to receive(:is_enabled).and_return(true)
end

And(/^the consumer's Alive Status is moved to outstanding$/) do
  alive_status = user.person.verification_type_by_name('Alive Status')
  alive_status.update(validation_status: 'outstanding')
end

And(/^the consumer's Alive Status is moved to rejected$/) do
  alive_status = user.person.verification_type_by_name('Alive Status')
  alive_status.update(validation_status: 'rejected')
end

And(/^the consumer's Alive Status is moved to verified$/) do
  user.person.verification_type_by_name('Alive Status').pass_type
end

Then(/^the Action Items table is not present$/) do
  expect(page).not_to have_content(l10n('insured.consumer_roles.upload_ridp_documents.action_items'))
end

Then(/^the Transaction History table is present$/) do
  expect(page).to have_content(l10n('insured.families.verifications.history.verification_history'))
end

And(/^.+ clicks on the back button of the Verification History page$/) do
  find(IvlVerificationHistory.back_to_verification_detail_btn).click
end

And(/^.+ clicks on the Document Detail breadcrumb$/) do
  find(IvlDocumentDetail.doc_detail_breadcrumb).click
end

Then(/^.+ should be in the Document Detail page$/) do
  expect(page).to have_content(l10n('insured.families.verifications.detail.verification_details'))
  expect(page).to have_content(l10n('insured.families.verifications.detail.document_upload'))
  expect(page).to have_content(l10n('insured.families.verifications.detail.admin_tools'))
end

Then(/^the consumer visits verification page$/) do
  visit verification_insured_families_path(tab: 'verification')
  sleep 50
  # after refactoring turbolinks and selectric, return interaction through class
  find_all("a", text: "Documents", exact: true, wait: 5)[0].click
  # find(".interaction-click-control-documents", wait: 5).click
end

Then(/^the consumer visits the verification tab$/) do
  visit verification_insured_families_path(tab: 'verification')
end

Then(/^the consumer should see the verifications household summary page$/) do
  expect(page).to have_content(l10n('insured.consumer_roles.upload_ridp_documents.outstanding_header'))
end

Then(/^the consumer should see the old verifications documents page$/) do
  expect(page).not_to have_content(l10n('insured.consumer_roles.upload_ridp_documents.action_items'))
  expect(page).to have_content(l10n('verification_documents'))
end

Then(/the consumer should (.*)see a (.*) item in the Action Items table/) do |negation, status|
  is_visible = !negation.present?
  if is_visible
    within IvlDocumentsPage.action_items_section do
      expect(page).to have_content "Action Items"
      expect(page).to have_content "1 Outstanding Document"
      within('table tbody tr') do
        expect(find('td:nth-child(1)')).to have_content('John Smith')
        expect(find('td:nth-child(2)')).to have_content('Citizenship')
        expect(find('td:nth-child(3)')).to have_content(status.capitalize)
        expect(find('td:nth-child(4)')).to have_content(TimeKeeper.date_of_record)
      end
    end
  else
    expect(page).not_to have_selector(IvlDocumentsPage.action_items_section)
  end
end

Then(/the consumer should (.*)see an outstanding member in the Household Members table (.*) date/) do |member_negation, date_negation|
  is_member_outstanding = !member_negation.include?('not')
  is_date_relevant = !date_negation.include?('out')
  within IvlDocumentsPage.household_members_section do
    expect(page).to have_content "Household Members"
    within('table tbody tr') do
      expect(page).send(is_member_outstanding ? :to : :not_to, have_selector(IvlDocumentsPage.unverified_member_icon))
      expect(find('td:nth-child(1)')).to have_content('John Smith')
      expect(find('td:nth-child(3)')).to have_content(is_member_outstanding ? 'Unverified' : 'Verified')
      expect(find('td:nth-child(4)')).to have_content(is_date_relevant ? TimeKeeper.date_of_record : 'Not Applicable')
    end
  end
end

When(/the consumer selects the action item for the actionable verification/) do
  find("#{IvlDocumentsPage.action_items_section} tbody tr").click
end

Then(/the consumer should see the verification detail page/) do
  expect(page).to have_content("Verification Details")
  expect(page).to have_content("We verify the information you give us using electronic data sources. If the data sources do not match the information you gave us, we need you to provide documents to prove what you told us.")
end

When(/the .* vists the verification detail page for a verification with (.*) status/) do |status|
  steps %(
    Given the consumer has a verification with #{status} status
    And the consumer visits the verification tab
    And the consumer selects a household member
    And the consumer selects the verification for the member
  )
end

When(/the consumer presses the Back to Individual button/) do
  find('a', text: "Back to Individual").click
end

When(/the consumer presses the Back to Verifications button/) do
  find('a', text: "Back to Verifications").click
end

Given(/the consumer selects the verification for the member/) do
  find("#{IvlDocumentsPage.individual_verifications_section} tbody tr", text: "Citizenship").click
end

When(/^the consumer vists the verification detail page$/) do
  step "the consumer vists the verification detail page for a verification with verified status"
end

Then(/the consumer should see the summary header (.*) the status reason/) do |negation|
  is_visible = !negation.include?('out')
  within IvlDocumentsPage.summary_header do
    ["Status Reasoning:", "Mock Reason"].each do |text|
      expect(page).send(is_visible ? :to : :not_to, have_content(text))
    end
  end
end

Then(/the consumer should the summary header with the (.*) status/) do |status|
  within IvlDocumentsPage.summary_header do
    expect(page).to have_content status.capitalize
  end
end

Then(/the consumer should (.*) a actionable status/) do |negation|
  is_visible = !negation.include?('not')
  within IvlDocumentsPage.summary_header do
    expect(page).send(is_visible ? :to : :not_to, have_selector(IvlDocumentsPage.actionable_status_icon))
  end
end

Then(/the consumer should (.*) the upload section/) do |negation|
  is_visible = !negation.include?('not')
  expect(page).send(is_visible ? :to : :not_to, have_selector(IvlDocumentsPage.upload_documents_section))
end

When(/the consumer selects a household member/) do
  find("#{IvlDocumentsPage.household_members_section} tbody tr").click
end

Then(/the consumer should see the individual detail page/) do
  expect(page).to have_selector('h1', text: 'John Smith')
  expect(page).to have_content(
    "We verify the information you provide us " \
    "using electronic data sources. " \
    "The data sources we check for each person depend on the information you provided on the application, " \
    "such as whether or not this person need health coverage. " \
    "Select a type of information we verify to view details and take any action needed."
  )
end

Then(/^the selectric class is visible$/) do
  visit(current_url)
  expect(page).to have_css('.selectric')
end

When(/^the consumer should see documents verification page$/) do
  expect(page).to have_content("We verify the information you provide us using electronic data sources, like the Federal Data Services Hub and the IRS.")
  expect(page).to have_content "Documents We Accept"
  expect(page).to have_content('Social Security Number')
end

When(/^the consumer is completely verified$/) do
  user.person.consumer_role.import!(OpenStruct.new({:determined_at => Time.now, :vlp_authority => "hbx"}))
  sleep 40
end

When(/^the consumer is completely verified from curam$/) do
  user.person.consumer_role.update_attributes(OpenStruct.new({:determined_at => Time.now, :vlp_authority => 'curam'}))
  user.person.consumer_role.import!
end

Then(/^verification types have to be visible$/) do
  expect(page).to have_content('Social Security Number')
  expect(page).to have_content('Citizenship')
end

Then(/^verification types should display as verified state$/) do
  expect(page).to have_content('Social Security Number')
  expect(page).to have_content('Citizenship')
  expect(page).to have_content('Verified')
end

Then(/^verification types should display as external source$/) do
  expect(page).to have_content('Social Security Number')
  expect(page).to have_content('Citizenship')
  expect(page).to have_content('External Source')
end

Given(/^consumer has outstanding verification and unverified enrollments$/) do
  family = user.person.primary_family
  rating_area = FactoryBot.create(:benefit_markets_locations_rating_area)
  enr = FactoryBot.create(:hbx_enrollment,
                           family: family,
                           household: family.active_household,
                           coverage_kind: "health",
                           effective_on: TimeKeeper.date_of_record - 2.months,
                           enrollment_kind: "open_enrollment",
                           kind: "individual",
                           submitted_at: TimeKeeper.date_of_record - 2.months,
                           rating_area_id: rating_area.id,
                           special_verification_period: TimeKeeper.date_of_record - 20.days)
  enr.hbx_enrollment_members << HbxEnrollmentMember.new(applicant_id: family.active_family_members[0].id,
                                                        eligibility_date: TimeKeeper.date_of_record - 2.months,
                                                        coverage_start_on: TimeKeeper.date_of_record - 2.months)
  enr.save!
  user.person.consumer_role.fail_residency!
end

Then(/^consumer should see Verification Due date label$/) do
  expect(page).to have_content('Due Date')
end

Then(/^.+ should not see the Alive Status verification type$/) do
  expect(page).to_not have_content('Deceased') #should only display to consumer if 'outstanding'
end

Then(/^.+ should see the Alive Status verification type$/) do
  expect(page).to have_content('Deceased')
end

Then(/^consumer should see Documents We Accept link$/) do
  expect(page).to have_content('Documents We Accept')
end

Then(/^Individual should see cost saving documents for evidences$/) do
  expect(page).to have_css(IvlDocumentsPage.income_evidence)
  expect(page).to have_content('Coverage from a job')
  expect(page).to have_content('Coverage from another program')
  expect(page).to have_content(l10n('faa.evidence_type_aces'))
end

Then(/^validate_and_record_publish_application_errors feature is (.*)$/) do |config|
  allow(EnrollRegistry[:validate_and_record_publish_application_errors].feature).to receive(:is_enabled).and_return(config == 'enabled')
end

When(/^evidence determination payload is failed to publish$/) do
  evidence_verification_request = instance_double(Operations::Fdsh::RequestEvidenceDetermination)
  allow(evidence_verification_request).to receive(:call).and_return(Dry::Monads::Failure("test"))
  allow(Operations::Fdsh::RequestEvidenceDetermination).to receive(:new).and_return(evidence_verification_request)
end

And(/^Individual clicks on Actions dropdown$/) do
  find_all('.v-type-actions')[-1].click
end

When(/^the user selects the (.+) option from the actions dropdown/) do |option|
  find('.v-type-actions').find('select').click
  find('option', text: option).click
end

When(/^the user selects the (.+) option from the extend due date dropdown/) do |option|
  find('#due-on-options').find('select').click
  find('option', text: option).click
  find('#manual-due-on').find('input').set(TimeKeeper.date_of_record + 1.year) if option == 'manual'
end

And(/^Admin clicks on esi evidence action dropdown$/) do
  find_all('.v-type-actions')[-3].click
end

And(/^Admin should see and click (.*) option$/) do |option|
  expect(page).to have_content(option)
  find(:xpath, IvlDocumentsPage.send("#{option.parameterize.underscore}_option".to_sym)).click
end

And(/^Admin clicks confirm$/) do
  if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    click_button 'Confirm'
  else
    find('.v-type-confirm-button').click
  end
end

Then(/the user should see the new date/) do
  expect(page).to have_content(TimeKeeper.date_of_record)
end

Then(/^Admin should see the error message ([^"]*)$/) do |error_message|
  expect(page).to have_content(error_message)
end

Then(/^Admin should see the esi evidence state as attested$/) do
  txt = IvlDocumentsPage.esi_evidence_row_for(@applicant.full_name)
  page.all(:css, txt).each do |element|
    expect(element).to have_selector('.label', text: 'Attested')
  end
end

Then(/^Individual should see view history option/) do
  expect(page).to have_content('View History')
end

Then(/^Admin navigates to view history section/) do
  expect(page).to have_content('View History')
  find(:xpath, IvlDocumentsPage.view_history_option).click
end

Then(/^Admin should see the failed request recorded in the view history table/) do
  expect(page).to have_content("Hub request failed")
end

And(/^Individual clicks on verify/) do
  find(:xpath, IvlDocumentsPage.verify_option).click
end

And(/^Individual Selects Reason/) do
  find('.col-md-3', text: 'Select Reason').click
  find('li', :text => 'Document in EnrollApp').click
  find('.v-type-confirm-button').click
end

Then(/^Individual should see verification history timestamp/) do
  expect(find_all('td')[0].text).not_to eql("")
end

And(/^Individual clicks on view history$/) do
  find(:xpath, IvlDocumentsPage.view_history_option).click
end

Then(/^Individual should see request histories and verification types$/) do
  expect(page).to have_content('Verification History')
  expect(page).to have_content('Fdsh Hub Call')
  expect(page).to have_content('Requested Hub for verification')
end

And(/^Individual clicks on cancel button$/) do
  find('.btn', text: 'Cancel').click
end

Then(/^Individual should not see view history table$/) do
  expect(page).not_to have_content('Verification History')
end
