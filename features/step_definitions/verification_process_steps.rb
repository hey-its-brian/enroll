module VerificationUser
  def user(*traits)
    attributes = traits.extract_options!
    @user ||= FactoryBot.create :user, *traits, attributes
  end
end
World(VerificationUser)

Then(/^Individual click continue button$/) do
  find(IvlPersonalInformation.continue_btn).click
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

Then(/^the user will see the date, action, and update reason for the extension action$/) do
  expect(page).to have_content TimeKeeper.date_of_record
  expect(page).to have_content "Update Reason"
  expect(page).to have_content "Transaction ID"
end

And(/^.+ lands in the Verifications page$/) do
  if EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)
    expect(page).to have_content "Verifications"
  else
    expect(page).to have_content "Documents"
  end
end

And(/the determination for the family has been built/) do
  family = user.person.primary_family.reload
  allow(family).to receive(:all_family_member_relations_defined).and_return(true)
  ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
end

And(/^.+ clicks on member with verified status$/) do
  find_all(IvlDocumentsPage.member_link).first.click
end

Given(/^I should see page for documents verification$/) do
  expect(page).to have_content "Documents We Accept"
  expect(page).to have_content('Social Security Number')
  expect(page).to have_content('We verify the information you provide us using electronic data sources')
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

Given(/the consumer has these verifications:/) do |table|
  table.hashes.each do |row|
    type = row["Type"]
    status = row["Status"]

    next if type.downcase == "none" || status.downcase == "none"

    step "the consumer has a #{type} verification with #{status} status"
  end
end

Given(/the consumer has a verification with history elements that have varying dates/) do
  family = user.person.primary_family
  application = FactoryBot.create(:application,
                                  family_id: family.id,
                                  created_at: TimeKeeper.date_of_record,
                                  aasm_state: "determined",
                                  effective_date: TimeKeeper.date_of_record)
  user_family_member_id = family.primary_family_member.id
  FactoryBot.create(:financial_assistance_applicant,
                    :with_income_evidence,
                    application: application,
                    is_primary_applicant: true,
                    family_member_id: user_family_member_id)
  income_evidence = application.applicants.where(family_member_id: user_family_member_id).first.income_evidence
  income_evidence.verification_histories.create(action: 'verify', update_reason: 'Document in EnrollApp', updated_by: 'admin@user.com')
  income_evidence.request_results.create(result: 'verified', source: 'FDSH IFSV', raw_payload: nil)
  ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family.reload)
end

def create_verification(type_name, validation_status:, inactive: false)
  person = user.person
  family = person.primary_family
  case type_name
  when "Citizenship", "Immigration status", "Social Security Number", "Alive Status", "American Indian Status"
    FactoryBot.create(:verification_type, type_name: type_name, validation_status: validation_status, update_reason: "Mock Reason", due_date: TimeKeeper.date_of_record, person: person, inactive: inactive)
  else
    case type_name
    when "Income"
      type = "income"
    when "Coverage from a job"
      type = "esi"
    when "Coverage from MaineCare"
      step "EnrollRegistry local_mec_evidence feature is enabled"
      type = "local_mec"
    when "Coverage from another program"
      type = "non_esi"
    end
    type += "_evidence"
    application = FactoryBot.create(:application,
                                    family_id: family.id,
                                    created_at: TimeKeeper.date_of_record,
                                    aasm_state: "determined",
                                    effective_date: TimeKeeper.date_of_record)
    user_family_member_id = family.primary_family_member.id
    FactoryBot.create(:financial_assistance_applicant,
                      "with_#{type}".to_sym,
                      application: application,
                      is_primary_applicant: true,
                      family_member_id: user_family_member_id)
    application.applicants.where(family_member_id: user_family_member_id).first.send(type).update_attributes(aasm_state: validation_status)
  end
  person.consumer_role.set(aasm_state: 'verified')
  step "the alive_status feature is enabled" if type_name == "Alive Status"
  ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family.reload)
end

Given(/^that the consumer has inactive verifications/) do
  create_verification('Immigration status', validation_status: 'verified', inactive: true)
end

Given(/the consumer has a(?: (.+))? verification with (\w+) status/) do |type, status|
  create_verification(type || "Citizenship", validation_status: status)
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

Then(/^the Verification History table is present$/) do
  expect(page).to have_content(l10n('insured.families.verifications.history.verification_history'))
end

Then(/^the Verification History table should be sorted by date in reverse order$/) do
  date_strs = all('table tbody tr').map { |row| row.find('td:nth-child(1)').text }
  dates = date_strs.map { |date_str| DateTime.strptime(date_str, '%m/%d/%Y %H:%M') }
  expect(dates).to eq(dates.sort.reverse)
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

Then(/^the (.*) visits the verification tab$/) do |user|
  if user == 'admin'
    visit family_index_dt_exchanges_hbx_profiles_path
    expect(page).to have_css('table')
    within('table') do
      find('tr:first-child a').click
    end
    expect(page).to have_content('Verifications')
  end
  visit verification_insured_families_path(tab: 'verification')
end

Then(/^the consumer should see the verifications household summary page$/) do
  expect(page).to have_content(l10n('insured.consumer_roles.upload_ridp_documents.outstanding_header'))
end

Then(/^the consumer should see the old verifications documents page$/) do
  expect(page).not_to have_content(l10n('insured.consumer_roles.upload_ridp_documents.action_items'))
  expect(page).to have_content(l10n('verification_documents'))
end

Then(/the consumer should have (\d+) items? in the Action Items table/) do |count|
  count = count.to_i

  if count > 0
    within IvlDocumentsPage.action_items_section do
      expect(page).to have_content "Action Items"

      expect(page).to have_content "#{count} Outstanding #{'Document'.pluralize(count.to_i)}"
      expect(page).to have_selector('table tbody tr', count: count.to_i)
      within('table tbody tr:first-child') do
        expect(find('td:nth-child(1)')).to have_content('John Smith')
        expect(find('td:nth-child(4)')).to have_content(TimeKeeper.date_of_record)
      end
    end
  else
    expect(page).not_to have_selector(IvlDocumentsPage.action_items_section)
  end
end

Then(/the consumer should see a household member with (.*) status (.*) date (.*)/) do |cumulative_status, date_status, warning_status|
  is_date_relevant = !date_status.include?('out')
  has_warning = warning_status.include?('with warning')
  within IvlDocumentsPage.household_members_section do
    expect(page).to have_content "Household Members"
    within('table tbody tr') do
      expect(page).send(has_warning ? :to : :not_to, have_selector(IvlDocumentsPage.unverified_member_icon))
      expect(find('td:nth-child(1)')).to have_content('John Smith')
      expect(find('td:nth-child(3)')).to have_content(cumulative_status)
      expect(find('td:nth-child(4)')).to have_content(is_date_relevant ? TimeKeeper.date_of_record : 'Not Applicable')
    end
  end
end

When(/the consumer has an inactive family member/) do
  FactoryBot.create(:family_member,
                    person: FactoryBot.create(:person, first_name: 'Inactive', last_name: 'Member'),
                    family: user.person.families.first,
                    is_active: false)
end

Then(/the consumer should see only active members in the Household Members table/) do
  expect(page).not_to have_content('Inactive Member')
end


Then(/the .* should (not )?see the Individual (.*) table/) do |negation, table_type|
  is_visible = negation.nil?
  section_selector = "individual_#{table_type.split.join('_').downcase}_section"
  if is_visible
    within IvlDocumentsPage.send(section_selector) do
      expect(page).to have_content "Verifications"
      within 'table' do
        within 'thead tr' do
          headers = ['Document Name', 'Status', 'Due Date']
          headers.compact.each_with_index do |header, index|
            expect(find("th:nth-child(#{index + 1})")).to have_content(header)
          end
        end
      end
    end
  else
    expect(page).not_to have_selector(IvlDocumentsPage.send(section_selector))
  end
end

When(/the consumer selects the action item for the actionable verification/) do
  find("#{IvlDocumentsPage.action_items_section} tbody tr").click
end

Then(/the consumer should see the verification detail page/) do
  expect(page).to have_content("Verification Details")
end

When(/the (.*) visits the verification detail page for a(?: (.+))? verification with (.*) status/) do |user, type, status|
  type_substring = type ? " #{type}" : ''
  steps %(
    Given the consumer has a#{type_substring} verification with #{status} status
    And the #{user} visits the verification tab
    And the #{user} selects a household member
    And the consumer selects the#{type_substring} verification for the member
  )
end

When(/the consumer presses the Back to Individual button/) do
  find('a', text: "Back to Individual").click
end

When(/the consumer presses the Back to Verifications button/) do
  find('a', text: "Back to Verifications").click
end

Given(/the consumer selects the(?: +(.+))? verification for the member/) do |type|
  type = "Deceased" if type == "Alive Status"
  type = type.titleize if type == "Immigration status"
  sleep 1
  all("#{IvlDocumentsPage.individual_verifications_section} tbody tr", text: type || "Citizenship").first.click
end

When(/^the consumer visits the verification detail page$/) do
  step "the consumer visits the verification detail page for a verification with verified status"
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
    expect(page).to have_content(/#{Regexp.escape(status)}/i)
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

Then(/the consumer (.*) see the (.*) verification row$/) do |negation, type|
  is_visible = !negation.include?('not')
  expect(page).send(is_visible ? :to : :not_to, have_css('tr', text: type))
end

When(/the .* selects a household member/) do
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

Then(/the consumer should see Individual disclaimer/) do
  expect(page).to have_content(
    "We verify the information you provide on your application using electronic data sources. A data matching inconsistency (DMI) occurs if the data " \
    "sources do not match the information you provided. When this occurs your verification status will be 'Outstanding' and you will need to provide documents to prove what you told us."
  )
  expect(page).to have_content(
    "We will send you reminder notices about which documents you must submit to verify the information. If you do not " \
    "provide documentation or resolve your DMI by the due date, you could lose your coverage or access to financial assistance, such as APTC and CSR."
  )
end

When("the consumer expands all accordions") do
  all('.accordion a[data-toggle="collapse"]').each do |accordion|
    accordion.click
    sleep 1
  end
end

Then(/^the admin actions dropdown should have options: (.*)$/) do |options_string|
  if options_string.strip == "(no options)"
    expect(page).not_to have_select('admin_actions')
  else
    all_possible_options = ['Verify', 'Reject', 'Call HUB', 'Set due date']
    expected_options = options_string.split(', ').map(&:strip)
    excluded_options = all_possible_options - expected_options

    expect(page).to have_select(with_options: expected_options)

    excluded_options.each do |excluded_option|
      expect(page).not_to have_select(with_options: [excluded_option])
    end
  end
end

Then(/the consumer should see the (.*) documents we accept section/) do |type|
  expect(VerificationDocumentsHelper.verify_content_for(type, page)).to be true
end

Then(/the user should (.*) see the set due date option/) do |negation|
  is_visible = !negation.include?('not')
  expect(page).send(is_visible ? :to : :not_to, have_select(with_options: ["Extend"]))
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

Then(/^the user should see (.*) in the reasons dropdown$/) do |reasons|
  sleep 1 # wait for fade
  reasons.split(', ').each do |reason|
    expect(page).to have_content(reason)
  end
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
  expect(page).to have_content(EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary) ? IvlDocumentDetail.verification_history_link : 'View History')
end

Then(/^the "View verification history" link should be visible$/) do
  expect(page).to have_selector(IvlDocumentDetail.verification_history_link)
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

Given(/^the consumer has an FAA application that was migrated$/) do
  family = user.person.primary_family
  current_year = TimeKeeper.date_of_record.year
  application = FactoryBot.create(
    :financial_assistance_application,
    family_id: family.id,
    assistance_year: current_year,
    aasm_state: "determined",
    origin: "migration",
    generation_reason: "manual",
    submitted_at: 10.days.ago
  )
  application.save!
end

Given(/^the consumer has a previous year FA application that needs verifications$/) do
  family = user.person.primary_family
  current_year = TimeKeeper.date_of_record.year
  application = FactoryBot.create(
    :financial_assistance_application,
    family_id: family.id,
    assistance_year: current_year,
    aasm_state: "determined",
    submitted_at: 5.days.ago
  )
  applicant = FactoryBot.create(
    :financial_assistance_applicant,
    :with_work_email,
    :with_work_phone,
    application: application,
    family_member_id: family.family_members.first.id
  )
  applicant.build_ivl_eligibility_with_evidences
  application.save!
  aptc_csr_eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: applicant)
  FactoryBot.create(:income_evidence, :outstanding, eligibility: aptc_csr_eligibility)
end

Given(/^the consumer has a determined QHP application$/) do
  family = user.person.primary_family
  renewal_year = TimeKeeper.date_of_record.year + 1
  application = FactoryBot.create(
    :individual_market_application,
    family_id: family.id,
    assistance_year: renewal_year,
    current_state: "determined",
    submitted_at: 3.days.ago
  )
  applicant = FactoryBot.create(
    :individual_market_applicant,
    :with_person_name,
    :with_demographics,
    :with_eligibilities,
    :with_home_address,
    application: application,
    family_member_id: family.family_members.first.id
  )
  FactoryBot.create(:individual_market_demographics, applicant: applicant)
  applicant.build_individual_market_evidences
  application.save!
  family.update_attributes(latest_application_gid: application.to_global_id.to_s)
  ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family.reload)
end

Then(/^.+ should see a previous year FA application needing verifications banner$/) do
  expect(page).to have_selector('div[data-cuke="previous-year-faa-application-needing-verifications-banner"]')
end

And(/^.+ clicks the link in the previous year application banner$/) do
  find('div[data-cuke="previous-year-faa-application-needing-verifications-banner"] a').click
end

Then(/^.+ should see the application id link$/) do
  expect(page).to have_selector('div[data-cuke="application-id-link"] a')
end

Then(/^.+ should be on the previous application page$/) do
  expect(page).to have_selector('h1[data-cuke="application-specific-verifications-title"]')
end

Then(/^there should be FA related inactive verifications listed$/) do
  expect(page).to have_selector('[data-cuke="individual-inactive-verifications"]')
  within('[data-cuke="individual-inactive-verifications"]') do
    expect(page).to have_content('Income')
    expect(page).to have_content('Outstanding')
  end
end
