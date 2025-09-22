# frozen_string_literal: true

Given(/^the qhp consumer is logged in$/) do
  login_as qhp_consumer, scope: :user
end

And(/^the qhp consumer is RIDP verified$/) do
  qhp_consumer.person.consumer_role.move_identity_documents_to_verified
end

And(/^the qhp consumer has an existing (.*?) application$/) do |status|
  qhp_application(status.to_sym)
end

And(/^the qhp consumer navigates to 'update application'$/) do
  hbx_profile = FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period)
  allow(HbxProfile).to receive(:current).and_return(hbx_profile)
  visit root_path
  click_link l10n('welcome.index.consumer_family_portal')
  click_link l10n('faa.applications', wait: 2)
  step 'clicks the "Update Application" link'
end

Given(/^clicks the "Update Application" link$/) do
  expect(page).to have_css(IvlQhpCurrentApplicationsPage.qhp_applicable_year_application_card, wait: 5)
  year = Date.today.year # target application will always be created when the test is run

  within(IvlQhpCurrentApplicationsPage.qhp_applicable_year_application_card) do
    click_button(l10n('actions'))
    click_link(l10n('insured.sbm.applications.actions.update_year', year: year))
  end
end

When(/^clicks the "View Eligibility Determination" for applicable application link$/) do
  expect(page).to have_css(IvlQhpCurrentApplicationsPage.qhp_applicable_year_application_card, wait: 5)

  within(IvlQhpCurrentApplicationsPage.qhp_applicable_year_application_card) do
    click_button(l10n('actions'))
    click_link(l10n('insured.sbm.applications.actions.view_eligibility'))
  end
end
