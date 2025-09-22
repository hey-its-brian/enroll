# frozen_string_literal: true

Then(/^the qhp consumer agrees and submits QHP application$/) do
  primary = qhp_application.primary_applicant
  # page can take some time to load, added 'wait' param to first instruction
  fill_in IvlQhpSubmitPage.qhp_submit_first_name, with: primary.person_name.given_name, wait: 10
  fill_in IvlQhpSubmitPage.qhp_submit_last_name, with: primary.person_name.family_name
  find(IvlQhpSubmitPage.qhp_submit_i_agree).click
  find('input[class*="interaction-click-control-submit-application"]').click
end

Then(/^the qhp consumer should see the eligibility determination page$/) do
  expect(page).to have_css(IvlQhpEligibilityResultsPage.qhp_continue_to_shop_for_plans, wait: 10)
end

Then(/^the qhp consumer should see the eligibility determination details page$/) do
  expect(page).to have_css(IvlQhpCommonElements.qhp_application_details_link, wait: 10)
  expect(page).to have_content(l10n('qhp_application.nav.results'))
end

And(/^the (.*?) applicant has (AI_AN|is_incarcerated|eligible_address|us_citizen|applying_coverage) marked as true$/) do |role, status|
  step "the user clicks the edit #{role} qhp applicant button"

  case status
  when 'AI_AN'
    step "user selects yes for qhp applicant's indian_tribe_member status"
  when 'is_incarcerated'
    step "user selects yes for qhp applicant's incarcerated status"
  when 'eligible_address'
    step "user enters a valid state address for qhp #{role} applicant"
  when 'us_citizen'
    step "user selects yes for qhp applicant's us_citizen status"
  when 'applying_coverage'
    step "user selects yes for qhp applicant's coverage requirement"
  end

  step 'user clicks save changes on the qhp application'
end

And(/^the (.*?) applicant has (AI_AN|is_incarcerated|eligible_address|us_citizen|applying_coverage) marked as false$/) do |role, status|
  step "the user clicks the edit #{role} qhp applicant button"

  case status
  when 'AI_AN'
    step "user selects no for qhp applicant's indian_tribe_member status"
  when 'is_incarcerated'
    step "user selects no for qhp applicant's incarcerated status"
  when 'eligible_address'
    step "user enters an invalid state address for qhp #{role} applicant"
  when 'us_citizen'
    step "user selects no for qhp applicant's us_citizen status"
  when 'applying_coverage'
    step "user selects no for qhp applicant's coverage requirement"
  end

  step 'user clicks save changes on the qhp application'
end

Then(/^the qhp consumer should see that none have uqhp eligibility$/) do
  expect(page).to_not have_css(IvlQhpEligibilityResultsPage.uqhp_eligible_section, wait: 5)
end

Then(/^the qhp consumer should see both applicants are not csr eligible$/) do
  expect(page).to_not have_css(IvlQhpEligibilityResultsPage.csr_eligible_section, wait: 5)
end

Then(/^the qhp consumer should see that (primary|dependent|both) have uqhp eligibility$/) do |role|
  expect(page).to have_content(l10n("qhp_application.results.uqhp_title"))
  applicants = determine_eligible_or_ineligible_applicants(role, qhp_application)

  within(IvlQhpEligibilityResultsPage.uqhp_eligible_section) do
    applicants.each do |applicant|
      expect(page).to have_content(applicant.person_name.given_name)
      expect(page).to have_content(applicant.person_name.family_name)
    end
  end
end

Then(/^the qhp consumer should see that (primary|dependent|both) have csr eligibility$/) do |role|
  expect(page).to have_content(l10n("faa.results.csr_nal_text"))
  applicants = determine_eligible_or_ineligible_applicants(role, qhp_application)

  within(IvlQhpEligibilityResultsPage.csr_eligible_section) do
    applicants.each do |applicant|
      expect(page).to have_content(applicant.person_name.given_name)
      expect(page).to have_content(applicant.person_name.family_name)
    end
  end
end

Then(/^the qhp consumer should see that (primary|dependent|both) are totally ineligible$/) do |role|
  expect(page).to have_content(l10n("faa.results.totally_ineligible_heading"))
  applicants = determine_eligible_or_ineligible_applicants(role, qhp_application)

  within(IvlQhpEligibilityResultsPage.totally_ineligible_section) do
    applicants.each do |applicant|
      expect(page).to have_content(applicant.person_name.given_name)
      expect(page).to have_content(applicant.person_name.family_name)
    end
  end
end

Then(/^the qhp consumer should see that (primary|dependent|both) did not apply for coverage$/) do |role|
  expect(page).to have_content(l10n("faa.results.not_applying_coverage_heading"))
  applicants = determine_eligible_or_ineligible_applicants(role, qhp_application)

  within(IvlQhpEligibilityResultsPage.not_applying_coverage_section) do
    applicants.each do |applicant|
      expect(page).to have_content(applicant.person_name.given_name)
      expect(page).to have_content(applicant.person_name.family_name)
    end
  end
end
