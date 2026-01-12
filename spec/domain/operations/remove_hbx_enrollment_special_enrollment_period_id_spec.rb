# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::RemoveHbxEnrollmentSpecialEnrollmentPeriod, type: :model, dbclean: :after_each do
  let(:operation) { described_class.new }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member) }
  let(:sep) { FactoryBot.create(:special_enrollment_period, family: family, start_on: TimeKeeper.date_of_record - 10.days, end_on: TimeKeeper.date_of_record - 2.days) }
  let(:new_sep) { FactoryBot.create(:special_enrollment_period, family: family, start_on: TimeKeeper.date_of_record - 10.days, end_on: TimeKeeper.date_of_record + 1.day) }
  let(:predecessor_enrollment) { FactoryBot.create(:hbx_enrollment, family: family, special_enrollment_period_id: sep.id) }
  let!(:enrollment) do
    FactoryBot.create(
      :hbx_enrollment,
      family: family,
      aasm_state: "coverage_selected",
      predecessor_enrollment_id: predecessor_enrollment.id,
      special_enrollment_period_id: sep.id,
      effective_on: TimeKeeper.date_of_record
    )
  end

  describe "failure" do
    it "returns Failure if year is blank" do
      result = operation.send(:validate, {})
      expect(result).to be_failure
      expect(result.failure).to eq("Missing Year")
    end
  end

  describe "success" do

    subject(:operation) { described_class.new }

    before do
      expect(enrollment.special_enrollment_period_id).not_to be_nil
      @result = operation.call({ year: sep.start_on.year })
    end

    it "removes the enrollment SEP id" do
      expect(@result).to be_success
      enrollment.reload
      expect(enrollment.special_enrollment_period_id).to be_nil
    end

    it 'generates a CSV file with the correct data' do
      expect(@result.success?).to be true
      enrollment.reload
      csv_file_name = @result.success.split(': ').last
      csv_data = CSV.parse(File.read(csv_file_name))
      date = TimeKeeper.date_of_record.strftime("%Y_%m_%d")
      filename = "#{Rails.root}/removed_enrollment_special_enrollment_period_ids_#{date}.csv"
      expect(File.exist?(filename)).to be true

      expect(csv_data[0]).to eq(['Primary Hbx Id', 'Enrollment Hbx Id', 'Enrollment Kind', 'Enrollment State', 'Special Enrollment Period Id', 'Enrollment Predecessor Hbx Id'])

      row1 = csv_data.find { |row| row[1] == enrollment.hbx_id }
      expect(row1).not_to be_nil
      expect(row1[0]).to eq(family.primary_person.hbx_id)
      expect(row1[4]).to be_empty
      expect(row1[5]).to be_present
    end
  end

  describe "#coinciding_applications?" do

    let(:application) do
      FactoryBot.create(
        :financial_assistance_application,
        family_id: family.id,
        submitted_at: enrollment.created_at,
        aasm_state: 'determined'
      )
    end

    before do
      enrollment.update(special_enrollment_period_id: new_sep.id)
      enrollment.workflow_state_transitions << WorkflowStateTransition.new(from_state: 'shopping',
                                                                           to_state: 'coverage_selected',
                                                                           event: 'select_coverage')
      application.workflow_state_transitions << WorkflowStateTransition.new(from_state: 'draft',
                                                                            to_state: 'determined',
                                                                            event: 'submit',
                                                                            transition_at: application.created_at - 5.seconds)
      application.save!
      enrollment.save!
    end

    it "removes the SEP id from the enrollment" do
      result = operation.call({ year: sep.start_on.year })
      expect(result).to be_success
      enrollment.reload
      expect(enrollment.special_enrollment_period_id).to be_nil
    end
  end

  describe "#reinstated_enrollment?" do

    let(:workflow_transition) do
      WorkflowStateTransition.new(from_state: 'shopping', to_state: 'coverage_reinstated', event: 'renew')
    end

    before do
      enrollment.special_enrollment_period_id = new_sep.id
      enrollment.workflow_state_transitions << workflow_transition
      enrollment.save!
    end

    it "returns true and removes the SEP id from the enrollment" do
      operation.call({ year: sep.start_on.year })
      enrollment.reload
      expect(enrollment.special_enrollment_period_id).to be_nil
    end
  end
end