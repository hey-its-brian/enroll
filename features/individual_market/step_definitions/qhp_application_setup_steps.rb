# frozen_string_literal: true

Given(/^the back to account feature is enabled$/) do
  allow(EnrollRegistry).to receive(:feature_enabled?).with(:back_to_account_all_shop).and_return(true)
  allow(EnrollRegistry).to receive(:feature_enabled?).and_call_original
end

Given(/^the user family has an eligibility determination$/) do
  create_mock_family_eligibility_determination
end

Given(/^the (.+?) is eligible for a qhp application$/) do |_user_type|
  login_as qhp_consumer, scope: :user
  hbx_profile = FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period)
  allow(HbxProfile).to receive(:current).and_return(hbx_profile)
  visit root_path
  click_link l10n('welcome.index.consumer_family_portal')
  find(IvlAuthorizationAndConsent.continue_btn).click
  find(IvlVerifyIdentity.pick_answer_a).click
  find(IvlVerifyIdentity.pick_answer_c).click
  find(IvlVerifyIdentity.submit_btn).click
  find(IvlVerifyIdentity.continue_btn).click
end

Given(/^the user opts out of IAP$/) do
  find(IvlIapHelpPayingForCoverage.no_radiobtn).click
  find(IvlIapHelpPayingForCoverage.continue_btn).click
end
