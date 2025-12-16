 # frozen_string_literal: true

require 'rails_helper'

RSpec.describe "ManuallyTriggerSavedEvent", type: :script do
  describe 'transitions without publishing events or invoking noisy callbacks' do
    let(:rating_area) { FactoryBot.create_default(:benefit_markets_locations_rating_area) }
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:consumer_role) { person.consumer_role }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:hbx_enrollment) do
      FactoryBot.create(
        :hbx_enrollment,
        :individual_unassisted,
        :with_health_product,
        family: family,
        household: family.active_household,
        coverage_kind: 'health',
        effective_on: TimeKeeper.date_of_record.beginning_of_month,
        consumer_role: consumer_role,
        rating_area_id: rating_area.id,
        aasm_state: "coverage_selected",
        generation_reason: "plan_shopping"
      )
    end

    let(:from_date) { TimeKeeper.date_of_record - 10.days }

    before do
      hbx_enrollment
      invoke_enrollment_saved_event_script(from_date)
    end

    it 'should generate csv' do
      report = Dir.glob("#{Rails.root}/enrollments_requiring_reconciliation_*.csv")
      expect(report).to_not be_empty
    end
  end

  after do
    csv_files = Dir.glob("#{Rails.root}/enrollments_requiring_reconciliation_*.csv")
    csv_files.each { |file| File.delete(file) if File.exist?(file) }
  end
end

def invoke_enrollment_saved_event_script(date)
  original_argv = ARGV.dup
  ARGV.replace([date.to_s])
  enrollment_saved_event_script = File.join(Rails.root, "script/hbx_enrollments/manually_trigger_saved_event.rb")
  load enrollment_saved_event_script
ensure
  ARGV.replace(original_argv)
end
