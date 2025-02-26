# frozen_string_literal: true

require "rails_helper"

RSpec.describe Exchanges::AssisterApplicantsHelper, dbclean: :after_each, :type => :helper do

  context "sort_by_latest_transition_time" do
    let(:person1) {FactoryBot.create(:person, :with_assister_role)}
    let(:person2) {FactoryBot.create(:person, :with_assister_role)}
    let(:person3) {FactoryBot.create(:person, :with_assister_role)}
    let(:people) {Person.exists(assister_role: true)}

    it "returns people array sorted by assister_role.latest_transition_time" do
      person1.assister_role.workflow_state_transitions.first.update_attributes(created_at: TimeKeeper.datetime_of_record - 6.days)
      person2.assister_role.workflow_state_transitions.first.update_attributes(created_at: TimeKeeper.datetime_of_record - 1.days)
      person3.assister_role.workflow_state_transitions.first.update_attributes(created_at: TimeKeeper.datetime_of_record - 2.days)
      expect(helper.sort_by_latest_transition_time(people)).to match_array([person2, person3, person1])
    end
  end
end
