# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::FinancialAssistance::DeleteInvalidApplicationRelationships do
  subject { described_class.new }

  let(:date_string) { Time.now.strftime('%Y_%m_%d') }
  let(:csv_path) { "#{Rails.root}/deleted_application_relationships_report_#{date_string}.csv" }

  before do
    DatabaseCleaner.clean
    # allow for generation of invalid relationships
    allow_any_instance_of(FinancialAssistance::Relationship).to receive(:valid?).and_return(true)
  end

  after do
    File.delete(csv_path) if File.exist?(csv_path)
  end

  describe '#call' do
    context 'when there are applications with invalid relationships' do
      let!(:valid_app) do
        application = FactoryBot.create(:financial_assistance_application)
        applicant1 = FactoryBot.create(:financial_assistance_applicant, application: application, is_primary_applicant: true)
        applicant2 = FactoryBot.create(:financial_assistance_applicant, application: application)

        application.relationships.create(
          applicant_id: applicant1.id,
          relative_id: applicant2.id,
          kind: 'child'
        )
        application.relationships.create(
          applicant_id: applicant2.id,
          relative_id: applicant1.id,
          kind: 'parent'
        )

        application
      end

      let!(:invalid_app_1) do
        application = FactoryBot.create(:financial_assistance_application)
        FactoryBot.create(:financial_assistance_applicant, application: application, is_primary_applicant: true)
        applicant = FactoryBot.create(:financial_assistance_applicant, application: application)
        application.relationships.create(
          relative_id: applicant.id,
          kind: 'child'
        )

        application
      end

      let!(:invalid_app_2) do
        application = FactoryBot.create(:financial_assistance_application)
        applicant = FactoryBot.create(:financial_assistance_applicant, application: application, is_primary_applicant: true)
        FactoryBot.create(:financial_assistance_applicant, application: application)
        application.relationships.create(
          applicant_id: applicant.id,
          kind: 'parent'
        )

        application
      end

      context "when mode is 'report'" do
        before do
          @result = subject.call(mode: 'update')
        end

        it 'returns success and the csv path' do
          expect(@result).to be_success
          expect(@result.success).to eq(csv_path)
        end

        it 'generates a CSV file with invalid app info' do
          expect(File).to exist(csv_path)
          csv_content = CSV.read(csv_path)
          headers = [
            'Application HBX ID',
            'Primary HBX ID',
            'AASM State',
            'Created At',
            'Relationships Before Deletion',
            'Relationships After Deletion'
          ]

          expect(csv_content.size).to eq(3)
          expect(csv_content[0]).to eq(headers)
          expect(csv_content[1]).to include(invalid_app_1.hbx_id)
          expect(csv_content[2]).to include(invalid_app_2.hbx_id)
        end

        it 'does not remove invalid relationships from applications' do
          invalid_app_1.reload
          invalid_app_2.reload

          expect(invalid_app_1.relationships.count).to eq(1)
          expect(invalid_app_2.relationships.count).to eq(1)
        end

        it 'does not affect apps with valid relationships' do
          valid_app.reload
          expect(valid_app.relationships.count).to eq(2)
        end
      end

      context "when mode is 'update'" do
        before do
          # de-mock the valid? method
          allow_any_instance_of(FinancialAssistance::Relationship).to receive(:valid?).and_call_original

          subject.call(mode: 'update')
        end

        it 'removes invalid relationships from applications' do
          invalid_app_1.reload
          invalid_app_2.reload

          expect(invalid_app_1.relationships.count).to eq(0)
          expect(invalid_app_2.relationships.count).to eq(0)
        end

        it 'does not affect apps with valid relationships' do
          valid_app.reload
          expect(valid_app.relationships.count).to eq(2)
        end
      end
    end

    context 'when there are no applications with invalid relationships' do
      it 'returns a failure' do
        result = subject.call(mode: 'report')

        expect(result).to be_failure
        expect(result.failure).to eq('No invalid applications found')
      end
    end

    context 'when an invalid mode is provided' do
      it 'returns a failure' do
        result = subject.call(mode: 'invalid_mode')

        expect(result).to be_failure
        expect(result.failure).to eq('Invalid mode')
      end
    end
  end
end
