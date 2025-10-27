# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'completed_evidence_due_dates rake tasks', type: :task, dbclean: :after_each do
  before do
    Rake.application.rake_require 'tasks/completed_evidence_due_dates'
    Rake::Task.define_task(:environment)
  end

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }
  let(:applicant) { FactoryBot.create(:financial_assistance_applicant, application: application) }
  let(:eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }

  shared_examples 'evidence processing' do
    it 'finds the correct applications' do
      expect { task.invoke }.to output(/Found #{expected_app_count} applications with evidences to process/).to_stdout
    end
  end

  describe 'completed_evidence_due_dates:fix' do
    let(:task_name) { 'completed_evidence_due_dates:fix' }
    let(:task) { Rake::Task[task_name] }

    before { task.reenable }

    context 'when evidences have due_on dates and are in completed states' do
      let!(:completed_evidence) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, due_on: Date.current + 30.days)
      end

      let!(:another_completed_evidence) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :attested, due_on: Date.current + 15.days)
      end

      let(:expected_app_count) { 1 }

      include_examples 'evidence processing'

      it 'clears due_on for evidences not in pending states' do
        task.invoke

        completed_evidence.reload
        another_completed_evidence.reload

        expect(completed_evidence.due_on).to be_nil
        expect(another_completed_evidence.due_on).to be_nil
      end

      it 'displays correct counts in output' do
        expect { task.invoke }.to output(/due_on updated for 2 evidences/).to_stdout
      end

      it 'includes rebuild message' do
        expect { task.invoke }.to output(/Please rebuild family determinations/).to_stdout
      end
    end

    context 'when evidences are in pending states' do
      let!(:pending_evidence) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :outstanding, due_on: Date.current + 30.days)
      end

      let!(:review_evidence) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :review, due_on: Date.current + 15.days)
      end

      let!(:rejected_evidence) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :rejected, due_on: Date.current + 10.days)
      end

      let(:expected_app_count) { 0 }

      include_examples 'evidence processing'

      it 'does not clear due_on for evidences in pending states' do
        task.invoke

        pending_evidence.reload
        review_evidence.reload
        rejected_evidence.reload

        expect(pending_evidence.due_on).to be_present
        expect(review_evidence.due_on).to be_present
        expect(rejected_evidence.due_on).to be_present
      end

      it 'updates zero evidences' do
        expect { task.invoke }.to output(/due_on updated for 0 evidences/).to_stdout
      end
    end

    context 'when evidences have no due_on date' do
      let!(:evidence_without_due_on) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, due_on: nil)
      end

      let(:expected_app_count) { 0 }

      include_examples 'evidence processing'

      it 'does not process evidences without due_on dates' do
        expect { task.invoke }.to output(/due_on updated for 0 evidences/).to_stdout
      end
    end

    context 'with multiple applications' do
      let(:person2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
      let(:family2) { FactoryBot.create(:family, :with_primary_family_member, person: person2) }
      let(:application2) { FactoryBot.create(:financial_assistance_application, family_id: family2.id) }
      let(:applicant2) { FactoryBot.create(:financial_assistance_applicant, application: application2) }
      let(:eligibility2) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant2) }

      let!(:evidence1) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, due_on: Date.current + 30.days)
      end

      let!(:evidence2) do
        FactoryBot.create(:income_evidence, eligibility: eligibility2, current_state: :attested, due_on: Date.current + 20.days)
      end

      let(:expected_app_count) { 2 }

      include_examples 'evidence processing'

      it 'processes multiple applications' do
        expect { task.invoke }.to output(/due_on updated for 2 evidences/).to_stdout

        evidence1.reload
        evidence2.reload

        expect(evidence1.due_on).to be_nil
        expect(evidence2.due_on).to be_nil
      end
    end
  end

  describe 'completed_evidence_due_dates:generate_impact_list' do
    let(:task_name) { 'completed_evidence_due_dates:generate_impact_list' }
    let(:task) { Rake::Task[task_name] }
    let(:csv_file_path) { "#{Rails.root}/completed_evidence_impact_#{Date.today.strftime('%Y_%m_%d')}.csv" }

    before { task.reenable }
    after { File.delete(csv_file_path) if File.exist?(csv_file_path) }

    context 'when evidences need reporting' do
      let!(:evidence1) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, due_on: Date.current + 30.days, key: 'income_evidence')
      end

      let!(:evidence2) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :attested, due_on: Date.current + 15.days, key: 'residency_evidence')
      end

      let(:expected_app_count) { 1 }

      include_examples 'evidence processing'

      it 'generates CSV report with correct data' do
        expect { task.invoke }.to output(/Generating impact list for completed evidences with due_on set/).to_stdout

        expect(File.exist?(csv_file_path)).to be true

        csv_content = File.read(csv_file_path)

        expect(csv_content).to include('Application Type')
        expect(csv_content).to include('Application HBX ID')
        expect(csv_content).to include('Application Assistance Year')
        expect(csv_content).to include('Application State')
        expect(csv_content).to include('Person HBX ID')
        expect(csv_content).to include('Eligibility Key')
        expect(csv_content).to include('Evidence Key')
        expect(csv_content).to include('Current State')
        expect(csv_content).to include('Due On')
        expect(csv_content).to include('Last Action')
        expect(csv_content).to include('Last Action Date')

        expect(csv_content).to include('FinancialAssistance::Application') # Application Type
        expect(csv_content).to include(application.hbx_id) # Application HBX ID
        expect(csv_content).to include(application.assistance_year.to_s) # Application Assistance Year
        expect(csv_content).to include(application.aasm_state) # Application State
        expect(csv_content).to include(applicant.person_hbx_id) # Person HBX ID
        expect(csv_content).to include('income_evidence')
        expect(csv_content).to include('residency_evidence')
        expect(csv_content).to include('verified')
        expect(csv_content).to include('attested')
      end

      it 'includes correct number of evidence records' do
        expect { task.invoke }.to output(/Generating CSV report with 2 evidence records/).to_stdout
      end
    end

    context 'when no evidences need reporting' do
      let(:expected_app_count) { 0 }

      include_examples 'evidence processing'

      it 'generates empty CSV report' do
        expect { task.invoke }.to output(/Generating CSV report with 0 evidence records/).to_stdout

        expect(File.exist?(csv_file_path)).to be true

        csv_content = File.read(csv_file_path)
        lines = csv_content.split("\n")
        expect(lines.length).to eq 1 # Only header row
      end
    end

    context 'when CSV generation fails' do
      let!(:evidence) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, due_on: Date.current + 30.days)
      end

      before do
        allow(File).to receive(:write).and_raise(StandardError.new("Permission denied"))
      end

      it 'handles CSV generation errors gracefully' do
        expect { task.invoke }.to output(/Error generating CSV: Permission denied/).to_stdout
      end
    end
  end
end
