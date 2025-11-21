# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'fix_evidence_is_satisfied rake tasks', type: :task, dbclean: :after_each do
  before do
    Rake.application.rake_require 'tasks/fix_evidence_is_satisfied'
    Rake::Task.define_task(:environment)
  end

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, assistance_year: 2026) }
  let(:applicant) { FactoryBot.create(:financial_assistance_applicant, application: application) }
  let(:eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }

  shared_examples 'evidence processing' do
    it 'finds the correct applications' do
      expect { task.invoke }.to output(/Found #{expected_app_count} applications with evidences to process/).to_stdout
    end
  end

  describe 'fix_evidence_is_satisfied:fix' do
    let(:task_name) { 'fix_evidence_is_satisfied:fix' }
    let(:task) { Rake::Task[task_name] }

    before { task.reenable }

    context 'when evidences are in completed states but is_satisfied is not true' do
      let!(:verified_evidence) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, is_satisfied: false)
      end

      let!(:attested_evidence) do
        FactoryBot.create(:esi_mec_evidence, eligibility: eligibility, current_state: :attested, is_satisfied: false)
      end

      let!(:nrr_evidence) do
        FactoryBot.create(:non_esi_mec_evidence, eligibility: eligibility, current_state: :negative_response_received, is_satisfied: false)
      end

      let(:expected_app_count) { 1 }

      include_examples 'evidence processing'

      it 'sets is_satisfied to true for evidences in completed states' do
        task.invoke

        verified_evidence.reload
        attested_evidence.reload
        nrr_evidence.reload

        expect(verified_evidence.is_satisfied).to be true
        expect(attested_evidence.is_satisfied).to be true
        expect(nrr_evidence.is_satisfied).to be true
      end

      it 'displays correct counts in output' do
        expect { task.invoke }.to output(/is_satisfied updated for 3 evidences across 1 eligibilities/).to_stdout
      end

      it 'includes rebuild message' do
        expect { task.invoke }.to output(/Please rebuild family determinations/).to_stdout
      end

      it 'calls determine_eligibility_state on processed eligibilities' do
        expect_any_instance_of(eligibility.class).to receive(:determine_eligibility_state).once
        task.invoke
      end
    end

    context 'when evidences are in satisfied states including pending and unverified' do
      let!(:pending_evidence) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :pending, is_satisfied: false)
      end

      let!(:unverified_evidence) do
        FactoryBot.create(:esi_mec_evidence, eligibility: eligibility, current_state: :unverified, is_satisfied: false)
      end

      let(:expected_app_count) { 1 }

      include_examples 'evidence processing'

      it 'sets is_satisfied to true for evidences in pending and unverified states' do
        task.invoke

        pending_evidence.reload
        unverified_evidence.reload

        expect(pending_evidence.is_satisfied).to be true
        expect(unverified_evidence.is_satisfied).to be true
      end

      it 'displays correct counts in output' do
        expect { task.invoke }.to output(/is_satisfied updated for 2 evidences across 1 eligibilities/).to_stdout
      end
    end

    context 'when evidences are in non-satisfied states' do
      let!(:outstanding_evidence) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :outstanding, is_satisfied: false)
      end

      let!(:review_evidence) do
        FactoryBot.create(:esi_mec_evidence, eligibility: eligibility, current_state: :review, is_satisfied: false)
      end

      let!(:rejected_evidence) do
        FactoryBot.create(:non_esi_mec_evidence, eligibility: eligibility, current_state: :rejected, is_satisfied: false)
      end

      let(:expected_app_count) { 0 }

      include_examples 'evidence processing'

      it 'does not update is_satisfied for evidences in non-satisfied states' do
        task.invoke

        outstanding_evidence.reload
        review_evidence.reload
        rejected_evidence.reload

        expect(outstanding_evidence.is_satisfied).to be false
        expect(review_evidence.is_satisfied).to be false
        expect(rejected_evidence.is_satisfied).to be false
      end

      it 'updates zero evidences' do
        expect { task.invoke }.to output(/is_satisfied updated for 0 evidences across 0 eligibilities/).to_stdout
      end
    end

    context 'when evidences are already correctly satisfied' do
      let!(:already_satisfied_evidence) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, is_satisfied: true)
      end

      let(:expected_app_count) { 0 }

      include_examples 'evidence processing'

      it 'does not process evidences that are already satisfied' do
        expect { task.invoke }.to output(/is_satisfied updated for 0 evidences across 0 eligibilities/).to_stdout
      end
    end

    context 'with different assistance years' do
      let(:application_2025) { FactoryBot.create(:financial_assistance_application, family_id: family.id, assistance_year: 2025) }
      let(:applicant_2025) { FactoryBot.create(:financial_assistance_applicant, application: application_2025) }
      let(:eligibility_2025) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant_2025) }

      let!(:evidence_2026) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, is_satisfied: false)
      end

      let!(:evidence_2025) do
        FactoryBot.create(:income_evidence, eligibility: eligibility_2025, current_state: :verified, is_satisfied: false)
      end

      let(:expected_app_count) { 2 }

      include_examples 'evidence processing'

      it 'processes applications from all assistance years' do
        expect { task.invoke }.to output(/is_satisfied updated for 2 evidences across 2 eligibilities/).to_stdout

        evidence_2026.reload
        evidence_2025.reload

        expect(evidence_2026.is_satisfied).to be true
        expect(evidence_2025.is_satisfied).to be true # Both should be updated since task processes all years
      end
    end

    context 'with multiple applications' do
      let(:person2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
      let(:family2) { FactoryBot.create(:family, :with_primary_family_member, person: person2) }
      let(:application2) { FactoryBot.create(:financial_assistance_application, family_id: family2.id, assistance_year: 2026) }
      let(:applicant2) { FactoryBot.create(:financial_assistance_applicant, application: application2) }
      let(:eligibility2) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant2) }

      let!(:evidence1) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, is_satisfied: false)
      end

      let!(:evidence2) do
        FactoryBot.create(:income_evidence, eligibility: eligibility2, current_state: :attested, is_satisfied: false)
      end

      let(:expected_app_count) { 2 }

      include_examples 'evidence processing'

      it 'processes multiple applications' do
        expect { task.invoke }.to output(/is_satisfied updated for 2 evidences across 2 eligibilities/).to_stdout

        evidence1.reload
        evidence2.reload

        expect(evidence1.is_satisfied).to be true
        expect(evidence2.is_satisfied).to be true
      end
    end

    context 'with IndividualMarket applications' do
      let(:im_application) { FactoryBot.create(:individual_market_application, family_id: family.id, assistance_year: 2026) }
      let(:im_applicant) { FactoryBot.create(:individual_market_applicant, application: im_application) }
      let(:im_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: im_applicant) }

      let!(:im_evidence) do
        FactoryBot.create(:income_evidence, eligibility: im_eligibility, current_state: :verified, is_satisfied: false)
      end

      let(:expected_app_count) { 1 }

      include_examples 'evidence processing'

      it 'processes IndividualMarket applications' do
        expect { task.invoke }.to output(/is_satisfied updated for 1 evidences across 1 eligibilities/).to_stdout

        im_evidence.reload
        expect(im_evidence.is_satisfied).to be true
      end
    end
  end

  describe 'fix_evidence_is_satisfied:generate_impact_list' do
    let(:task_name) { 'fix_evidence_is_satisfied:generate_impact_list' }
    let(:task) { Rake::Task[task_name] }
    let(:csv_file_path) { "#{Rails.root}/evidence_is_satisfied_impact_#{Date.today.strftime('%Y_%m_%d')}.csv" }

    before { task.reenable }
    after { File.delete(csv_file_path) if File.exist?(csv_file_path) }

    context 'when evidences need reporting including pending and unverified states' do
      let!(:evidence1) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, is_satisfied: false, key: 'income_evidence')
      end

      let!(:evidence2) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :pending, is_satisfied: false, key: 'residency_evidence')
      end

      let!(:evidence3) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :unverified, is_satisfied: false, key: 'citizenship_evidence')
      end

      let(:expected_app_count) { 1 }

      include_examples 'evidence processing'

      it 'generates CSV report with correct data' do
        expect { task.invoke }.to output(/Generating impact list for evidences in completed states with is_satisfied not true/).to_stdout

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
        expect(csv_content).to include('Is Satisfied')
        expect(csv_content).to include('Last Action')
        expect(csv_content).to include('Last Action Date')

        expect(csv_content).to include('FinancialAssistance::Application') # Application Type
        expect(csv_content).to include(application.hbx_id) # Application HBX ID
        expect(csv_content).to include(application.assistance_year.to_s) # Application Assistance Year
        expect(csv_content).to include(application.aasm_state) # Application State
        expect(csv_content).to include(applicant.person_hbx_id) # Person HBX ID
        expect(csv_content).to include('income_evidence')
        expect(csv_content).to include('residency_evidence')
        expect(csv_content).to include('citizenship_evidence')
        expect(csv_content).to include('verified')
        expect(csv_content).to include('pending')
        expect(csv_content).to include('unverified')
      end

      it 'includes correct number of evidence records' do
        expect { task.invoke }.to output(/Generating CSV report with 3 evidence records/).to_stdout
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
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, is_satisfied: false)
      end

      before do
        allow(File).to receive(:write).and_raise(StandardError.new("Permission denied"))
      end

      it 'handles CSV generation errors gracefully' do
        expect { task.invoke }.to output(/Error generating CSV: Permission denied/).to_stdout
      end
    end

    context 'with different assistance years (all years processed)' do
      let(:application_2025) { FactoryBot.create(:financial_assistance_application, family_id: family.id, assistance_year: 2025) }
      let(:applicant_2025) { FactoryBot.create(:financial_assistance_applicant, application: application_2025) }
      let(:eligibility_2025) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant_2025) }

      let!(:evidence_2026) do
        FactoryBot.create(:income_evidence, eligibility: eligibility, current_state: :verified, is_satisfied: false, key: 'income_2026')
      end

      let!(:evidence_2025) do
        FactoryBot.create(:income_evidence, eligibility: eligibility_2025, current_state: :pending, is_satisfied: false, key: 'income_2025')
      end

      let(:expected_app_count) { 2 }

      include_examples 'evidence processing'

      it 'processes all assistance years (no year constraint)' do
        expect { task.invoke }.to output(/Generating CSV report with 2 evidence records/).to_stdout

        expect(File.exist?(csv_file_path)).to be true
        csv_content = File.read(csv_file_path)

        expect(csv_content).to include('income_2026')
        expect(csv_content).to include('income_2025')
        expect(csv_content).to include('2026')
        expect(csv_content).to include('2025')
      end
    end
  end
end
