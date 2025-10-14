# frozen_string_literal: true

Then(/^user should see an option to add a new member$/) do
  expect(page).to have_content(l10n('family_information'))
  expect(page).to have_content(l10n('add_new_member_to_household'))
end

Then(/^user should see an 'edit' option for each applicant$/) do
  total_applicants = qhp_application.non_primary_applicants.count

  expect(page).to have_css('[data-cuke="edit-primary-applicant"]', count: 1)
  expect(page).to have_css('[data-cuke="edit-dependent-applicant"]', count: total_applicants)
end

Then(/^a new qhp application should be created$/) do
  expect(page).to have_content(l10n('add_new_member_to_household'))
  expect(IndividualMarket::Application.count).to eq(1)
end

When(/user clicks the Add Member to Household button$/) do
  find('span', text: l10n('add_new_member_to_household')).click
end

Then(/^the user visits the current applications page$/) do
  visit '/insured/sbm/applications/current_applications'
end

Then(/^the (.*?) selects 'Applications' from the sidebar$/) do |_user_type|
  within('.portal-nav') do
    click_link(l10n('qhp_application.show.applications'))
  end
end

Then(/^the user should see the current applications page$/) do
  expect(page).to have_content(l10n('qhp_application.show.applications'))
  expect(page).to have_content(l10n('insured.sbm.applications.application_history_description1'))
end

Then(/^the user should not see a prospective year application$/) do
  expect(page).not_to have_css(IvlQhpCurrentApplicationsPage.qhp_prospective_year_application_card)
end

Then(/^the user should not see a prospective year application banner$/) do
  expect(page).not_to have_css(IvlQhpCurrentApplicationsPage.prospective_year_banner)
end

Then(/^the user should see a prospective year application banner$/) do
  expect(page).to have_css(IvlQhpCurrentApplicationsPage.prospective_year_banner)
end

And(/^the user clicks on the start application accordion$/) do
  find(IvlQhpCurrentApplicationsPage.year_application_accordion).click(wait: 5)
end

Then(/^the user should see the current during oe text$/) do
  expect(page).to have_css(IvlQhpCurrentApplicationsPage.current_during_oe_text)
end

Then(/^the user should not see the current during oe text$/) do
  expect(page).not_to have_css(IvlQhpCurrentApplicationsPage.current_during_oe_text)
end

Then(/^the user should see the current not during oe text$/) do
  expect(page).to have_css(IvlQhpCurrentApplicationsPage.current_not_during_oe_text)
end

Then(/^the user should not see the current not during oe text$/) do
  expect(page).not_to have_css(IvlQhpCurrentApplicationsPage.current_not_during_oe_text)
end

Then(/^the user should see the applicable year draft or no application card$/) do
  expect(page).to have_css(IvlQhpCurrentApplicationsPage.qhp_applicable_draft_or_no_application_card)
end

Then(/^the user should see the applicable year application card$/) do
  expect(page).to have_css(IvlQhpCurrentApplicationsPage.qhp_applicable_year_application_card)
end

Then(/^the user should see the prospective year application card$/) do
  expect(page).to have_css(IvlQhpCurrentApplicationsPage.qhp_prospective_year_application_card)
end

Then(/^the user should see the previous year draft or no application card$/) do
  expect(page).to have_css(IvlQhpCurrentApplicationsPage.qhp_previous_draft_or_no_application_card)
end

When(/^the user clicks Back To My Account section on the left navigation$/) do
  find('a#back-button').click(wait: 10)
end

Then(/^the user will see a confirmation modal for not submitting their application$/) do
  expect(page).to have_css('a.btn', text: l10n('insured.leaving_modal.leave_without_submitting'))
end

Then(/^the user leaves without submitting$/) do
  click_link(l10n('insured.leaving_modal.leave_without_submitting'))
end

Then(/^the user should see the contact preferences page$/) do
  expect(page).to have_content(l10n('insured.preferences.contact_methods'))
  expect(page).to have_content(l10n('insured.preferences.language_preferences'))
end

Then(/^the user should see the review application page$/) do
  expect(page).to have_content(l10n('faa.review.review_and_submit'))
end

Then(/^the user should see the submit application page$/) do
  expect(page).to have_content(l10n('qhp_application.attestation.title'))
end

Then(/^the qhp consumer clicks continue to next step to the '(.*?)' page$/) do |_page_name|
  sleep 2
  expect(page).to have_css(IvlQhpCommonElements.qhp_continue_to_next_step, visible: :visible, wait: 10)

  if page.current_url.include?('review')
    all(IvlQhpCommonElements.qhp_continue_to_next_step, wait: 10)[1].click
  else
    find_all(IvlQhpCommonElements.qhp_continue_to_next_step, wait: 10).last.click
  end
end

And(/^the qhp consumer completes and submits the qhp application$/) do
  step "the qhp consumer clicks continue to next step to the 'preferences' page"
  step "the qhp consumer clicks continue to next step to the 'review' page"
  step "the qhp consumer clicks continue to next step to the 'submit' page"
  step 'the qhp consumer agrees and submits QHP application'
end
