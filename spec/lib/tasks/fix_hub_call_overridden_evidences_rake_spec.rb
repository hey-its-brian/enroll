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

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke
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

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke
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

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke
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

        Rake::Task['fix_hub_call_overridden_evidences:fix'].invoke

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
end