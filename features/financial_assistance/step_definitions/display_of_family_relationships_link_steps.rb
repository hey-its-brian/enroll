# frozen_string_literal: true

Given(/^the Family Relationships link displays in the left column of the page$/) do
  expect(page).to have_css('.interaction-click-control-family-relationships', text: l10n('faa.nav.family_relationships'))
end

Then(/^the Family Relationships link is disabled$/) do
  page.should have_no_link(l10n('faa.nav.family_relationships'))
end

Given(/^the Family Relationships link is enabled$/) do
  page.should have_link(l10n('faa.nav.family_relationships'))
end

When(/^the user clicks the Family Relationships link$/) do
  find(:xpath,'//*[@id="left-navigation"]/li[3]/a').click
  sleep 2
end

Then(/^the user will navigate to the Family relationships page$/) do
  expect(page).to have_css('.interaction-click-control-family-relationships', text: l10n('faa.nav.family_relationships'))
  expect(page).to have_css('div', text: l10n("en.faa.tax_info.household_member").upcase)
end