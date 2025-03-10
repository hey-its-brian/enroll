#frozen_string_literal: true

Given(/^Admin is on the new Bulk Notice view$/) do
  load 'app/models/admin/bulk_notice.rb'
  visit new_exchanges_bulk_notice_path
end

When(/^Admin selects Employer$/) do
  select 'Employer'
end

When(/^Admin selects Broker Agency$/) do
  select 'Broker Agency'
end

When(/^Admin selects Assister Agency$/) do
  select 'Assister Agency'
end

When(/^Admin selects General Agency$/) do
  select 'General Agency'
end

When(/^Admin fills form with (.*?) FEIN$/) do |name|
  fein = case name
         when "Employer"
           employer("ACME").fein
         when "BrokerAgency"
           broker_agency_profile("ACME").fein
         when "AssisterAgency"
           assister_agency_profile("ACME").fein
         end
  @current_fein = fein
  fill_in "bulk-notice-audience-identifiers", with: fein
  textarea = find("#bulk-notice-audience-identifiers")
  textarea.click
  find("#bulk-notice-audience-identifiers").click
  find("#bulk-notice-audience-identifiers:focus", wait: 2)

  textarea.native.send_keys :tab
  expect(page).to have_css(".badge-blue, .badge-alt-blue")
end

Then(/^Admin should see (.*?) badge$/) do |name|
  hbx_id = case name
           when "Employer"
             employer("ACME").hbx_id
           when "BrokerAgency"
             broker_agency_profile("ACME").hbx_id
           when "AssisterAgency"
             assister_agency_profile("ACME").hbx_id
           end
  expect(page).to have_css('span.badge', text: hbx_id)
end

When(/^Admin fills in the rest of the form$/) do
  fill_in "admin_bulk_notice_subject", with: "Subject"
  fill_in "admin_bulk_notice_body", with: "Other Content"
end

When(/^Admin clicks on Preview button$/) do
  find('#preview_submit').click
end

Then(/^Admin should see the Preview Screen$/) do
  expect(page).to have_css('h1', text: l10n("preview"))
end
