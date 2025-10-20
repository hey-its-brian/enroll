# frozen_string_literal: true

Then(/the consumer should see Expert page navigation link/) do
  within ".portal-nav" do
    expect(page).to have_selector IvlExpertPage.expert_navigation_link
    expect(page).to have_link "My Broker"
  end
end

When(/the consumer goes to the Expert page/) do
  find(IvlExpertPage.expert_navigation_link).click
end

When(/the consumer selects Select an Assister button/) do
  find(IvlExpertPage.select_an_assister_btn).click
end

Then(/the consumer should see the Help with Plan Shopping modal/) do
  expect(page).to have_selector("h3", text: /Find An Assister/)
end
