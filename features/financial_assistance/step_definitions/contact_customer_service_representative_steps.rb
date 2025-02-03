#frozen_string_literal: true

When(/the consumer clicks the Get Help Signing Up Button?/) do
  find('.interaction-click-control-get-help-signing-up').click
end

Then(/they should see the Contact Customer Support and Certified Applicant Counselor links?/) do
  page.should have_css('.interaction-click-control-help-from-a-customer-service-representative', text: l10n('insured.plan_shoppings.help_from_a_customer_service_representative'))
  page.should have_css('.interaction-click-control-help-from-a-certified-applicant-counselor-\\(cac\\)', text: l10n('insured.plan_shoppings.help_from_a_certified_applicant_counselor'))
end

Then(/they should not see the Contact Customer Support and Certified Applicant Counselor links?/) do
  page.should_not have_css('.interaction-click-control-help-from-a-customer-service-representative', text: l10n('insured.plan_shoppings.help_from_a_customer_service_representative'))
  page.should_not have_css('.interaction-click-control-help-from-a-certified-applicant-counselor-\\(cac\\)', text: l10n('insured.plan_shoppings.help_from_a_certified_applicant_counselor'))
end
