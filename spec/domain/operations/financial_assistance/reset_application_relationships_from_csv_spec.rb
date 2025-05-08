# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::FinancialAssistance::ResetApplicationRelationshipsFromCSV do
  describe '#call' do
    let(:subject) { described_class.new }
    let(:csv_path) { Rails.root.join('spec', 'test_data', 'application_reset_test.csv') }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member) }
    let(:application) { FactoryBot.create(:application, family: family) }
    let(:applicant1) { FactoryBot.create(:applicant, application: application, is_primary_applicant: true) }
    let(:applicant2) { FactoryBot.create(:applicant, application: application) }
    let(:applicant3) { FactoryBot.create(:applicant, application: application) }

    before do
      application.applicants = [applicant1, applicant2, applicant3]

      application.relationships.build(applicant_id: applicant1.id, relative_id: applicant2.id, kind: 'spouse')
      application.relationships.build(applicant_id: applicant2.id, relative_id: applicant1.id, kind: 'spouse')
      application.relationships.build(applicant_id: applicant1.id, relative_id: applicant3.id, kind: 'child')
      application.relationships.build(applicant_id: applicant3.id, relative_id: applicant1.id, kind: 'parent')
      application.relationships.build(applicant_id: applicant2.id, relative_id: applicant3.id, kind: 'child')
      application.relationships.build(applicant_id: applicant3.id, relative_id: applicant2.id, kind: 'parent')
      application.save!

      FileUtils.mkdir_p(File.dirname(csv_path))
      CSV.open(csv_path, 'w') do |csv|
        csv << ['Application HBX ID']
        csv << [application.hbx_id]
      end
    end

    after do
      File.delete(csv_path) if File.exist?(csv_path)
    end

    context 'with valid params' do
      it 'returns a success' do
        result = subject.call(csv_path: csv_path)

        expect(result).to be_success
        expect(result.success).to eq('Completed processing applications')
      end

      it 'resets relationships for applications in the CSV' do
        expect(application.relationships.count).to eq(6)

        subject.call(csv_path: csv_path)

        application.reload
        expect(application.relationships.count).to eq(0)
      end
    end

    context 'when csv_path is missing' do
      it 'returns a failure' do
        result = subject.call({})

        expect(result).to be_failure
        expect(result.failure).to eq('Missing csv_path')
      end
    end

    context 'when csv file does not exist' do
      it 'returns a failure' do
        result = subject.call(csv_path: 'nonexistent_file.csv')

        expect(result).to be_failure
        expect(result.failure).to eq('CSV file not found at nonexistent_file.csv')
      end
    end

    context 'when csv file is empty or has no HBX IDs' do
      before do
        CSV.open(csv_path, 'w') do |csv|
          csv << ['Application HBX ID']
        end
      end

      it 'returns a failure' do
        result = subject.call(csv_path: csv_path)

        expect(result).to be_failure
        expect(result.failure).to eq('No HBX IDs found in CSV')
      end
    end
  end
end
