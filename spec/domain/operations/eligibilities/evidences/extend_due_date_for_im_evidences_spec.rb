# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Eligibilities::ExtendDueDateForImEvidences, type: :operation do
  let(:operation) { described_class.new }
  let(:start_date) { Date.new(2025,10,16)}
  let(:extension_days) { 7 }

  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let!(:hbx_enrollment) { FactoryBot.create(:hbx_enrollment, :with_enrollment_members, family: family, aasm_state: 'coverage_selected', kind: 'individual') }
  let(:current_application) { FactoryBot.create(:individual_market_application, family_id: family.id) }

  let(:first_notice_time) { start_date.beginning_of_day + 1.hour }
  let(:first_notice) { OpenStruct.new(subject: 'Action Needed - Submit Documents', created_at: first_notice_time) }

  let(:eligibility) { instance_double('Eligibilities::V3::Eligibility') }
  let(:evidence1) { double('Eligibilities::V3::Evidence', key: 'income', current_state: 'outstanding', due_on: start_date + 1, updated_at: first_notice_time) }
  let(:evidence2) { double('Eligibilities::V3::Evidence', key: 'citizenship', current_state: 'rejected', due_on: start_date + 2, updated_at: first_notice_time) }
  let(:applicant) { double('Applicant') }
  let(:applicant_hbx_id) { person.hbx_id }
  let(:timestamp) { Time.current.strftime('%Y_%m_%d_%H%M%S') }
  let(:output_path) { Rails.root.join("dr_consumers_current_outstanding_or_rejected_#{timestamp}.csv").to_s }

  before do
    allow(Person).to receive(:where).and_return([person])

    allow(person).to receive(:primary_family).and_return(family)
    allow(person).to receive_message_chain(:inbox, :messages, :where, :order_by, :first).and_return(first_notice)

    allow(family).to receive(:latest_application).and_return(current_application)
    allow(current_application).to receive(:class).and_return(IndividualMarket::Application)
    allow(current_application).to receive(:save!).and_return(true)

    allow(current_application).to receive(:applicants).and_return([applicant])
    allow(applicant).to receive(:person_hbx_id).and_return(applicant_hbx_id)
    allow(applicant).to receive_message_chain(:eligibilities, :where, :first).and_return(eligibility)
    allow(eligibility).to receive(:evidences).and_return([evidence1, evidence2])
    allow(evidence1).to receive(:manually_extend_due_date).and_return(true)
    allow(evidence2).to receive(:manually_extend_due_date).and_return(true)
  end

  it 'generates CSV with extended due dates for accepted evidences' do
    result = operation.call(start_date: "2025/10/16", extension_days: extension_days)

    expect(result).to be_success
    value = result.value!
    expect(value[:rows_count]).to eq(1)

    csv = CSV.read(value[:output_path])
    headers = csv.first
    row = csv.second

    expect(headers).to include('applicant_hbx_id')
    expect(headers).to include('evidence_key_1', 'current_evidence_state_1', 'old_due_on_1', 'new_due_on_1')

    expect(row[0]).to eq(person.hbx_id)
    expect(row[1]).to eq(first_notice.subject)
    expect(row[6]).to eq(applicant_hbx_id)

    expect(row).to include('income')
    expect(row).to include('outstanding')
    expect(row).to include(evidence1.due_on.to_s)
    expect(row).to include((TimeKeeper.date_of_record + extension_days).to_s)

    expect(row).to include('citizenship')
    expect(row).to include('rejected')
    expect(row).to include(evidence2.due_on.to_s)

    File.delete(value[:output_path]) if File.exist?(value[:output_path])
  end

  it 'skips evidences not in accepted states' do
    allow(eligibility).to receive(:evidences).and_return([double('Eligibilities::V3::Evidence', key: 'income', current_state: 'verified', due_on: start_date + 1)])

    result = operation.call(start_date: "2025/10/16", extension_days: extension_days)

    expect(result).to be_success
    value = result.value!
    expect(value[:rows_count]).to eq(0)

    File.delete(result.value![:output_path]) if result.success? && File.exist?(result.value![:output_path])
  end
end
