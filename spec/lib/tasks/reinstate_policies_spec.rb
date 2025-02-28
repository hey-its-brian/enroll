# frozen_string_literal: true

require 'rails_helper'

describe 'Reinstate HBX terminated enrollments', :dbclean => :around_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:enrollment) { FactoryBot.create(:hbx_enrollment, :terminated, family: family) }

  before do
    load File.expand_path("#{Rails.root}/lib/tasks/reinstate_policies.rake", __FILE__)
    Rake::Task.define_task(:environment)
    Rake::Task["reinstate_policies:reinstate"].reenable
    Rake::Task["reinstate_policies:reinstate"].invoke([enrollment.hbx_id])
  end

  it 'should nullify the term reason' do
    expect(enrollment.reload.terminate_reason).to eq nil
  end

  context 'when the family has a determination' do
    shared_context 'family determination setup' do |validation_status, expected_due_date|
      before do
        FactoryBot.create(:verification_type, type_name: "Citizenship", validation_status: validation_status, due_date: TimeKeeper.date_of_record + 1.year, person: person)
        ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family, effective_date: TimeKeeper.date_of_record)
      end

      it "should #{expected_due_date.nil? ? 'not ' : ''}create a new reasonable opportunity period" do
        expect(family.eligibility_determination.subjects.first.eligibility_states.where(:eligibility_item_key => 'aca_individual_market_eligibility').first.earliest_due_date).to eq expected_due_date
      end
    end

    [
      { status: 'outstanding', due_date: TimeKeeper.date_of_record + 1.year },
      { status: 'rejected', due_date: TimeKeeper.date_of_record + 1.year },
      { status: 'review', due_date: TimeKeeper.date_of_record + 1.year },
      { status: 'negative_response_received', due_date: nil },
      { status: 'verified', due_date: nil },
      { status: 'pending', due_date: nil }
    ].each do |scenario|
      context "when the family has a #{scenario[:status]} status determination" do
        include_context 'family determination setup', scenario[:status], scenario[:due_date]
      end
    end
  end
end
