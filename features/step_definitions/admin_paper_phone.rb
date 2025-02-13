When(/^I see the (.*?) link$/) do |method|
  find_link(method)
end

Then(/^the Paper action should not be actionable$/) do
  find("#dc-resident-application")['class'].split[1] == 'blocking'
end
