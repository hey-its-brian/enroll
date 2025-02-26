# frozen_string_literal: true

And(/^.+ visits the Edit Assister Applicant page for (.*?) of agency (.*?)$/) do |assister_name, legal_name|
  assister_role = assign_assister_to_assister_agency(assister_name, legal_name)
  person = assister_role.person
  url = "/exchanges/assister_applicants/#{person.id}/edit"
  visit(url)
end

And(/^.+ edits the assister application and clicks update$/) do
  # This page was unable to update in the past
  click_button('Update')
end

Then(/^.+should see a success message that the assister application was successfully updated$/) do
  expect(page).to have_content("Assister applicant successfully updated.")
end
