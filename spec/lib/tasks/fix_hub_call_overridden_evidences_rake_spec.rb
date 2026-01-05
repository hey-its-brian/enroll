# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'fix_hub_call_overridden_evidences rake tasks', type: :task, dbclean: :around_each do
  before(:all) do
    Rake.application.rake_require 'tasks/fix_hub_call_overridden_evidences'
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    Rake::Task['fix_hub_call_overridden_evidences:fix'].reenable
  end

  let(:family) { FactoryBot.create(:family, :with_primary_family_member) }
  let(:person) { family.primary_applicant.person }
  let(:application) do
    FactoryBot.create(:financial_assistance_application,
                      family_id: family.id,
                      assistance_year: 2024,
                      aasm_state: 'determined',
                      origin: 'admin')
  end
  let(:applicant) do
    FactoryBot.create(:applicant,
                      application: application,
                      person_hbx_id: person.hbx_id,
                      family_member_id: family.primary_applicant.id)
  end
  let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }

  describe 'fix_hub_call_overridden_evidences:fix' do
    context 'when restricting to specific family ids' do
      let(:other_family) { FactoryBot.create(:family, :with_primary_family_member) }
      let(:other_person) { other_family.primary_applicant.person }
      let(:other_application) do
        FactoryBot.create(:financial_assistance_application,
                          family_id: other_family.id,
                          assistance_year: 2024,
                          aasm_state: 'determined',
                          origin: 'admin')
      end
      let(:other_applicant) do
        FactoryBot.create(:applicant,
                          application: other_application,
                          person_hbx_id: other_person.hbx_id,
                          family_member_id: other_family.primary_applicant.id)
      end
      let(:other_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: other_applicant) }

      let!(:income_evidence) do
        evidence = FactoryBot.create(:income_evidence,
                                     eligibility: aptc_csr_eligibility,
                                     current_state: :outstanding)
        evidence.state_histories.destroy_all

        base_time = 1.minute.ago
        evidence.state_histories.create!(
          from_state: :pending,
          to_state: :outstanding,
          event: :move_to_outstanding,
          transition_at: base_time,
          effective_on: Date.current,
          created_at: base_time,
          updated_at: base_time
        )
        evidence.state_histories.create!(
          from_state: :pending,
          to_state: :review,
          event: :move_to_review,
          transition_at: base_time + 2.seconds,
          effective_on: Date.current,
          created_at: base_time + 2.seconds,
          updated_at: base_time + 2.seconds
        )

        evidence.reload
        evidence
      end

      let!(:other_income_evidence) do
        evidence = FactoryBot.create(:income_evidence,
                                     eligibility: other_eligibility,
                                     current_state: :outstanding)
        evidence.state_histories.destroy_all

        base_time = 1.minute.ago
        evidence.state_histories.create!(
          from_state: :pending,
          to_state: :outstanding,
          event: :move_to_outstanding,
          transition_at: base_time,
          effective_on: Date.current,
          created_at: base_time,
          updated_at: base_time
        )
        evidence.state_histories.create!(
          from_state: :pending,
          to_state: :review,
          event: :move_to_review,
          transition_at: base_time + 3.seconds,
          effective_on: Date.current,
          created_at: base_time + 3.seconds,
          updated_at: base_time + 3.seconds
        )

        evidence.reload
        evidence
      end

      before do
        family.update!(latest_application_gid: application.to_global_id)
        other_family.update!(latest_application_gid: other_application.to_global_id)
        allow($stdout).to receive(:puts)
      end

      it 'limits processing to the provided families' do
        csv_data = []
        csv_mock = double('csv')
        allow(csv_mock).to receive(:<<) { |row| csv_data << row }
        allow(CSV).to receive(:open).and_yield(csv_mock)

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke('outstanding', 'report', family.id.to_s)

        expect(csv_data.size).to eq(1)
        expect(csv_data.first.first).to eq(family.id.to_s)
      end
    end

    context 'with evidence that does not meet the criteria' do
      let!(:income_evidence) do
        evidence = FactoryBot.create(:income_evidence,
                                     eligibility: aptc_csr_eligibility,
                                     current_state: :verified) # Not outstanding
        evidence.save!
        evidence
      end

      before do
        family.update!(latest_application_gid: application.to_global_id)
        allow($stdout).to receive(:puts)
      end

      it 'does not process evidence that is not outstanding' do
        allow(CSV).to receive(:open).and_yield(double('csv', :<< => nil))

        expect(income_evidence).not_to receive(:call_hub)

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke('outstanding', 'report')
      end
    end

    context 'with evidence with insufficient state histories' do
      let!(:income_evidence) do
        evidence = FactoryBot.create(:income_evidence,
                                     eligibility: aptc_csr_eligibility,
                                     current_state: :outstanding)

        # Only one state history
        evidence.state_histories.build(
          from_state: :pending,
          to_state: :outstanding,
          transition_at: Time.current,
          effective_on: Date.current,
          event: :move_to_outstanding,
          created_at: Time.current,
          updated_at: Time.current
        )

        evidence.save!
        evidence
      end

      before do
        family.update!(latest_application_gid: application.to_global_id)
        allow($stdout).to receive(:puts)
      end

      it 'does not process evidence with less than 2 state histories' do
        allow(CSV).to receive(:open).and_yield(double('csv', :<< => nil))

        expect(income_evidence).not_to receive(:call_hub)

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke('outstanding', 'report')
      end
    end

    context 'with evidence with transitions too far apart' do
      let!(:income_evidence) do
        evidence = FactoryBot.create(:income_evidence,
                                     eligibility: aptc_csr_eligibility,
                                     current_state: :outstanding)

        base_time = 2.minutes.ago

        # First state transition
        evidence.state_histories.build(
          from_state: :pending,
          to_state: :outstanding,
          transition_at: base_time,
          effective_on: Date.current,
          event: :move_to_outstanding,
          created_at: base_time,
          updated_at: base_time
        )

        # Second state transition (more than 10 seconds apart)
        evidence.state_histories.build(
          from_state: :pending,
          to_state: :review,
          transition_at: base_time + 15.seconds,
          effective_on: Date.current,
          event: :move_to_review,
          created_at: base_time + 15.seconds,
          updated_at: base_time + 15.seconds
        )

        evidence.save!
        evidence
      end

      before do
        family.update!(latest_application_gid: application.to_global_id)
        allow($stdout).to receive(:puts)
      end

      it 'does not process evidence with transitions more than 10 seconds apart' do
        allow(CSV).to receive(:open).and_yield(double('csv', :<< => nil))

        expect(income_evidence).not_to receive(:call_hub)

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke('outstanding', 'report')
      end
    end

    context 'with migration application' do
      let(:migration_application) do
        FactoryBot.create(:financial_assistance_application,
                          family_id: family.id,
                          assistance_year: 2024,
                          aasm_state: 'determined',
                          origin: 'migration')
      end

      before do
        family.update!(latest_application_gid: migration_application.to_global_id)
        allow($stdout).to receive(:puts)
      end

      it 'skips migration applications' do
        csv_data = []
        allow(CSV).to receive(:open).and_yield(double('csv', :<< => ->(row) { csv_data << row }))

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke('outstanding', 'report')

        # Should complete without processing any evidence (no CSV data)
        expect(csv_data).to be_empty
      end
    end

    context 'with missing created_at timestamps' do
      let!(:income_evidence) do
        evidence = FactoryBot.create(:income_evidence,
                                     eligibility: aptc_csr_eligibility,
                                     current_state: :outstanding)

        # Clear any existing state histories
        evidence.state_histories.clear

        base_time = 2.minutes.ago

        # Create state histories where first one has missing created_at
        evidence.state_histories.build(
          from_state: :pending,
          to_state: :outstanding,
          transition_at: base_time,
          effective_on: Date.current,
          event: :move_to_outstanding,
          created_at: nil,  # Missing created_at - this should trigger the log message
          updated_at: base_time
        )

        evidence.state_histories.build(
          from_state: :pending,
          to_state: :review,
          transition_at: base_time + 5.seconds,
          effective_on: Date.current,
          event: :move_to_review,
          created_at: base_time + 5.seconds,
          updated_at: base_time + 5.seconds
        )

        evidence.save!
        evidence
      end

      before do
        family.update!(latest_application_gid: application.to_global_id)
        allow($stdout).to receive(:puts)
      end
    end
  end

  describe 'fix_hub_call_overridden_evidences:fix[rejected]' do
    let(:mode) { 'fix' }

    context 'with rejected evidence without application_determination' do
      let!(:income_evidence) do
        evidence = FactoryBot.create(:income_evidence,
                                     eligibility: aptc_csr_eligibility,
                                     current_state: :rejected)

        base_time = 2.minutes.ago

        # State transitions without application_determination comment
        evidence.state_histories.build(
          from_state: :pending,
          to_state: :outstanding,
          transition_at: base_time,
          effective_on: Date.current,
          event: :move_to_outstanding,
          created_at: base_time,
          updated_at: base_time
        )

        evidence.state_histories.build(
          from_state: :pending,
          to_state: :rejected,
          transition_at: base_time + 5.seconds,
          effective_on: Date.current,
          event: :move_to_rejected,
          created_at: base_time + 5.seconds,
          updated_at: base_time + 5.seconds
        )

        evidence.save!
        evidence
      end

      before do
        family.update!(latest_application_gid: application.to_global_id)
      end

      it 'does not process rejected evidence without application_determination' do
        allow(CSV).to receive(:open).and_yield(double('csv', :<< => nil))

        expect(income_evidence).not_to receive(:call_hub)

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke('rejected', mode)
      end
    end

    context 'with rejected evidence with insufficient states after application_determination' do
      let!(:income_evidence) do
        evidence = FactoryBot.create(:income_evidence,
                                     eligibility: aptc_csr_eligibility,
                                     current_state: :rejected)

        base_time = 2.minutes.ago

        # Application determination
        evidence.state_histories.build(
          from_state: :initial,
          to_state: :pending,
          transition_at: base_time,
          effective_on: Date.current,
          event: :move_to_pending,
          comment: 'application_determination',
          created_at: base_time,
          updated_at: base_time
        )

        # Only one state after application_determination (need at least 2)
        evidence.state_histories.build(
          from_state: :pending,
          to_state: :rejected,
          transition_at: base_time + 5.seconds,
          effective_on: Date.current,
          event: :move_to_rejected,
          created_at: base_time + 5.seconds,
          updated_at: base_time + 5.seconds
        )

        evidence.save!
        evidence
      end

      before do
        family.update!(latest_application_gid: application.to_global_id)
      end

      it 'does not process rejected evidence with insufficient states after app determination' do
        allow(CSV).to receive(:open).and_yield(double('csv', :<< => nil))

        expect(income_evidence).not_to receive(:call_hub)

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke('rejected', mode)
      end
    end

    context 'with valid rejected evidence meeting criteria' do
      let!(:income_evidence) do
        evidence = FactoryBot.create(:income_evidence,
                                     eligibility: aptc_csr_eligibility,
                                     current_state: :rejected)

        evidence.state_histories.destroy_all
        base_time = 2.minutes.ago

        # Application determination
        evidence.state_histories.create!(
          from_state: :initial,
          to_state: :pending,
          transition_at: base_time,
          effective_on: Date.current,
          event: :move_to_pending,
          comment: 'application_determination',
          created_at: base_time,
          updated_at: base_time
        )

        # First state after application_determination
        evidence.state_histories.create!(
          from_state: :pending,
          to_state: :attested,
          transition_at: base_time + 1.second,
          effective_on: Date.current,
          event: :move_to_attested,
          created_at: base_time + 1.second,
          updated_at: base_time + 1.second
        )

        # Second state after application_determination (race condition - same from_state, different to_state, within 10 seconds)
        evidence.state_histories.create!(
          from_state: :pending,
          to_state: :outstanding,
          transition_at: base_time + 2.seconds,
          effective_on: Date.current,
          event: :move_to_outstanding,
          created_at: base_time + 2.seconds,
          updated_at: base_time + 2.seconds
        )

        # Later transition to rejected
        evidence.state_histories.create!(
          from_state: :outstanding,
          to_state: :rejected,
          transition_at: base_time + 1.minute,
          effective_on: Date.current,
          event: :move_to_rejected,
          created_at: base_time + 1.minute,
          updated_at: base_time + 1.minute
        )

        evidence.reload
        evidence
      end

      before do
        family.update!(latest_application_gid: application.to_global_id)
      end

      it 'generates CSV report with valid rejected evidence' do
        csv_data = []
        csv_mock = double('csv')
        allow(csv_mock).to receive(:<<) { |row| csv_data << row }
        allow(CSV).to receive(:open).and_yield(csv_mock)

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke('rejected', mode)

        # Should have processed the evidence
        expect(csv_data).not_to be_empty
        expect(csv_data.first[4]).to eq('income_evidence')  # evidence_key
        expect(csv_data.first[5]).to eq(:rejected)  # current_state
      end
    end

    context 'when mode is report' do
      let(:mode) { 'report' }

      let!(:income_evidence) do
        evidence = FactoryBot.create(:income_evidence,
                                     eligibility: aptc_csr_eligibility,
                                     current_state: :rejected)

        evidence.state_histories.destroy_all
        base_time = 2.minutes.ago

        evidence.state_histories.create!(
          from_state: :initial,
          to_state: :pending,
          transition_at: base_time,
          effective_on: Date.current,
          event: :move_to_pending,
          comment: 'application_determination',
          created_at: base_time,
          updated_at: base_time
        )

        evidence.state_histories.create!(
          from_state: :pending,
          to_state: :attested,
          transition_at: base_time + 1.second,
          effective_on: Date.current,
          event: :move_to_attested,
          created_at: base_time + 1.second,
          updated_at: base_time + 1.second
        )

        evidence.state_histories.create!(
          from_state: :pending,
          to_state: :outstanding,
          transition_at: base_time + 2.seconds,
          effective_on: Date.current,
          event: :move_to_outstanding,
          created_at: base_time + 2.seconds,
          updated_at: base_time + 2.seconds
        )

        evidence.state_histories.create!(
          from_state: :outstanding,
          to_state: :rejected,
          transition_at: base_time + 1.minute,
          effective_on: Date.current,
          event: :move_to_rejected,
          created_at: base_time + 1.minute,
          updated_at: base_time + 1.minute
        )

        evidence.reload
        evidence
      end

      before do
        family.update!(latest_application_gid: application.to_global_id)
      end

      it 'does not call hub' do
        allow(CSV).to receive(:open).and_yield(double('csv', :<< => nil))

        expect(income_evidence).not_to receive(:call_hub)

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke('rejected', mode)
      end

      it 'does not rebuild family determination' do
        allow(CSV).to receive(:open).and_yield(double('csv', :<< => nil))

        expect(family).not_to receive(:reset_latest_application)

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke('rejected', mode)
      end
    end

    context 'with evidence rejected multiple times' do
      let!(:income_evidence) do
        evidence = FactoryBot.create(:income_evidence,
                                     eligibility: aptc_csr_eligibility,
                                     current_state: :rejected)

        evidence.state_histories.destroy_all
        base_time = 2.minutes.ago

        # Application determination
        evidence.state_histories.create!(
          from_state: :initial,
          to_state: :pending,
          transition_at: base_time,
          effective_on: Date.current,
          event: :move_to_pending,
          comment: 'application_determination',
          created_at: base_time,
          updated_at: base_time
        )

        # Race condition transitions
        evidence.state_histories.create!(
          from_state: :pending,
          to_state: :attested,
          transition_at: base_time + 1.second,
          effective_on: Date.current,
          event: :move_to_attested,
          created_at: base_time + 1.second,
          updated_at: base_time + 1.second
        )

        evidence.state_histories.create!(
          from_state: :pending,
          to_state: :outstanding,
          transition_at: base_time + 2.seconds,
          effective_on: Date.current,
          event: :move_to_outstanding,
          created_at: base_time + 2.seconds,
          updated_at: base_time + 2.seconds
        )

        # First rejection
        evidence.state_histories.create!(
          from_state: :outstanding,
          to_state: :rejected,
          transition_at: base_time + 10.seconds,
          effective_on: Date.current,
          event: :move_to_rejected,
          created_at: base_time + 10.seconds,
          updated_at: base_time + 10.seconds
        )

        # Back to attested
        evidence.state_histories.create!(
          from_state: :rejected,
          to_state: :attested,
          transition_at: base_time + 20.seconds,
          effective_on: Date.current,
          event: :move_to_attested,
          created_at: base_time + 20.seconds,
          updated_at: base_time + 20.seconds
        )

        # Second rejection
        evidence.state_histories.create!(
          from_state: :attested,
          to_state: :rejected,
          transition_at: base_time + 30.seconds,
          effective_on: Date.current,
          event: :move_to_rejected,
          created_at: base_time + 30.seconds,
          updated_at: base_time + 30.seconds
        )

        evidence.reload
        evidence
      end

      before do
        family.update!(latest_application_gid: application.to_global_id)
      end

      it 'processes evidence with multiple rejections' do
        csv_data = []
        csv_mock = double('csv')
        allow(csv_mock).to receive(:<<) { |row| csv_data << row }
        allow(CSV).to receive(:open).and_yield(csv_mock)

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke('rejected', mode)

        # Should have processed the evidence
        expect(csv_data).not_to be_empty
        expect(csv_data.first[4]).to eq('income_evidence')  # evidence_key
        expect(csv_data.first[5]).to eq(:rejected)  # current_state
      end
    end
  end
end
