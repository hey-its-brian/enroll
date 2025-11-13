# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'fix_null_family_member_id rake tasks', type: :task, dbclean: :after_each do
  before do
    Rake.application.rake_require 'tasks/fix_null_family_member_id'
    Rake::Task.define_task(:environment)
  end

  describe 'fix_null_family_member_id:generate_impact_list' do
    let(:task_name) { 'fix_null_family_member_id:generate_impact_list' }
    let(:task) { Rake::Task[task_name] }

    before { task.reenable }

    context 'when there are applications with nil family_member_id' do
      let!(:family) { FactoryBot.create(:family, :with_primary_family_member) }
      let!(:primary_applicant) { family.primary_applicant }
      let!(:application) do
        FactoryBot.create(:individual_market_application,
                          family_id: family.id,
                          current_state: :determined)
      end
      let!(:applicant) do
        FactoryBot.create(:individual_market_applicant,
                          application: application,
                          family_member_id: nil)
      end

      it 'generates impact list and CSV report' do
        expect(File).to receive(:write).with(
          a_string_matching(/null_family_member_id_impact_\d{4}_\d{2}_\d{2}\.csv/),
          a_string_including(application.id.to_s)
        )

        expect { task.invoke }.to output(
          a_string_including("Found 1 applications with nil family_member_id applicants")
            .and(including(primary_applicant.hbx_id))
            .and(including("CSV report generated"))
        ).to_stdout
      end

      it 'includes correct data in CSV' do
        csv_content = nil
        expect(File).to receive(:write) do |_filename, content|
          csv_content = content
        end

        task.invoke

        expect(csv_content).to include(application.id.to_s)
        expect(csv_content).to include(primary_applicant.hbx_id)
        expect(csv_content).to include(family.id.to_s)
        expect(csv_content).to include('determined')
      end
    end

    context 'when there are no applications with nil family_member_id' do
      let!(:family) { FactoryBot.create(:family, :with_primary_family_member) }
      let!(:application) do
        FactoryBot.create(:individual_market_application,
                          family_id: family.id,
                          current_state: :determined)
      end
      let!(:applicant) do
        FactoryBot.create(:individual_market_applicant,
                          application: application,
                          family_member_id: BSON::ObjectId.new)
      end

      it 'reports no applications found' do
        expect(File).not_to receive(:write)

        expect { task.invoke }.to output(
          a_string_including("Found 0 applications with nil family_member_id applicants")
            .and(including("No applications found with nil family_member_id applicants"))
        ).to_stdout
      end
    end

    context 'when an error occurs' do
      before do
        allow(IndividualMarket::Application).to receive(:where).and_raise(StandardError, 'Test error')
      end

      it 'handles errors gracefully' do
        expect { task.invoke }.to output(
          a_string_including("Error generating impact list: Test error")
        ).to_stdout
      end
    end
  end

  describe 'fix_null_family_member_id:fix' do
    let(:task_name) { 'fix_null_family_member_id:fix' }
    let(:task) { Rake::Task[task_name] }

    before { task.reenable }

    context 'with CRM number' do
      let!(:family) { FactoryBot.create(:family, :with_primary_family_member) }
      let!(:application) do
        FactoryBot.create(:individual_market_application,
                          family_id: family.id,
                          current_state: :determined)
      end
      let!(:applicant) do
        FactoryBot.create(:individual_market_applicant,
                          application: application,
                          family_member_id: nil)
      end

      it 'uses the provided CRM number' do
        task.invoke('29001')

        application.reload
        state_history = application.state_histories.last
        expect(state_history.reason).to include('CRM 29001')
        expect(state_history.comment).to include('CRM 29001')
      end
    end

    context 'with multiple applications' do
      let!(:family1) { FactoryBot.create(:family, :with_primary_family_member) }
      let!(:family2) { FactoryBot.create(:family, :with_primary_family_member) }
      let!(:application1) do
        FactoryBot.create(:individual_market_application,
                          family_id: family1.id,
                          current_state: :determined)
      end
      let!(:application2) do
        FactoryBot.create(:individual_market_application,
                          family_id: family2.id,
                          current_state: :determined)
      end
      let!(:applicant1) do
        FactoryBot.create(:individual_market_applicant,
                          application: application1,
                          family_member_id: nil)
      end
      let!(:applicant2) do
        FactoryBot.create(:individual_market_applicant,
                          application: application2,
                          family_member_id: nil)
      end

      it 'processes all applications' do
        expect { task.invoke }.to output(
          a_string_including("Found 2 applications to process")
            .and(including("Successfully processed: 2"))
            .and(including("Errors encountered: 0"))
        ).to_stdout

        [application1, application2].each do |app|
          app.reload
          expect(app.current_state).to eq(:cancelled)
        end
      end
    end

    context 'when save fails for one application' do
      let!(:family1) { FactoryBot.create(:family, :with_primary_family_member) }
      let!(:family2) { FactoryBot.create(:family, :with_primary_family_member) }
      let!(:application1) do
        FactoryBot.create(:individual_market_application,
                          family_id: family1.id,
                          current_state: :determined)
      end
      let!(:application2) do
        FactoryBot.create(:individual_market_application,
                          family_id: family2.id,
                          current_state: :determined)
      end
      let!(:applicant1) do
        FactoryBot.create(:individual_market_applicant,
                          application: application1,
                          family_member_id: nil)
      end
      let!(:applicant2) do
        FactoryBot.create(:individual_market_applicant,
                          application: application2,
                          family_member_id: nil)
      end

      before do
        allow(application1).to receive(:save!).and_raise(StandardError, 'Save failed')
        allow(IndividualMarket::Application).to receive_message_chain(:where, :where).and_return([application1, application2])
      end

      it 'handles errors and continues processing' do
        expect { task.invoke }.to output(
          a_string_including("Successfully processed: 1")
            .and(including("Errors encountered: 1"))
            .and(including("Error processing application #{application1.id}: Save failed"))
        ).to_stdout
      end
    end

    context 'when no applications found' do
      it 'reports no applications to process' do
        expect { task.invoke }.to output(
          a_string_including("Found 0 applications to process")
            .and(including("No applications found to process"))
        ).to_stdout
      end
    end

    context 'when an error occurs during query' do
      before do
        allow(IndividualMarket::Application).to receive(:where).and_raise(StandardError, 'Query failed')
      end

      it 'handles errors gracefully' do
        expect { task.invoke }.to output(
          a_string_including("Error running fix: Query failed")
        ).to_stdout
      end
    end
  end
end
