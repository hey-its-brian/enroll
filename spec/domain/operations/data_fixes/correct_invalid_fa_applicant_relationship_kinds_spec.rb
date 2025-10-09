# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::DataFixes::CorrectInvalidFaApplicantRelationshipKinds, type: :model, dbclean: :after_each do
  before :all do
    DatabaseCleaner.clean

    file_path1 = Rails.root.join("invalid_fa_applicant_relationship_kinds_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
    File.delete(file_path1) if File.exist?(file_path1)
    file_path2 = Rails.root.join("invalid_fa_applicant_relationship_kinds_data_fix_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
    File.delete(file_path2) if File.exist?(file_path2)
  end

  let(:primary) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: primary) }
  let(:fa_application) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }

  let(:primary_applicant_id) { BSON::ObjectId.new }
  let(:dependent1_applicant_id) { BSON::ObjectId.new }
  let(:dependent2_applicant_id) { BSON::ObjectId.new }

  let(:relationships) do
    fa_application.relationships.build(
      {
        kind: 'self',
        applicant_id: primary_applicant_id,
        relative_id: dependent1_applicant_id
      }
    )

    fa_application.relationships.build(
      {
        kind: 'other_relationship',
        applicant_id: dependent1_applicant_id,
        relative_id: dependent2_applicant_id
      }
    )
    fa_application.save(validate: false)
  end

  before :each do
    relationships
  end

  describe '#call' do
    context 'when action_type is data_fix' do
      it 'fixes invalid person relationships' do
        expect(subject.call(action_type: 'data_fix').success?).to be_truthy
      end

      it 'fixes invalid fa applicant relationships with correct actions' do
        subject.call(action_type: 'data_fix')
        file_path = Rails.root.join("invalid_fa_applicant_relationship_kinds_data_fix_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
        expect(File.exist?(file_path)).to be_truthy

        csv_data = CSV.read(file_path, headers: true)
        expect(csv_data.length).to eq(2)
        row1 = csv_data[0]
        expect(row1['Primary Person Hbx ID']).to eq(primary.hbx_id)
        expect(row1['FA Application Hbx ID']).to eq(fa_application.hbx_id)
        expect(row1['FA Application Assistance Year']).to eq(fa_application.assistance_year.to_s)
        expect(row1['FA Application AASM State']).to eq(fa_application.aasm_state)
        expect(row1['FA Application Transfer ID']).to be_blank
        expect(row1['Applicant ID']).to eq(primary_applicant_id.to_s)
        expect(row1['Relative ID']).to eq(dependent1_applicant_id.to_s)
        expect(row1['Invalid Relationship Kind']).to eq('self')
        expect(row1['Action Taken']).to eq('Destroyed relationship')

        row2 = csv_data[1]
        expect(row2['Primary Person Hbx ID']).to eq(primary.hbx_id)
        expect(row2['FA Application Hbx ID']).to eq(fa_application.hbx_id)
        expect(row2['FA Application Assistance Year']).to eq(fa_application.assistance_year.to_s)
        expect(row2['FA Application AASM State']).to eq(fa_application.aasm_state)
        expect(row2['FA Application Transfer ID']).to be_blank
        expect(row2['Applicant ID']).to eq(dependent1_applicant_id.to_s)
        expect(row2['Relative ID']).to eq(dependent2_applicant_id.to_s)
        expect(row2['Invalid Relationship Kind']).to eq('unrelated')
        expect(row2['Action Taken']).to eq("Updated from other_relationship to unrelated")
      end
    end

    context 'when action_type is report' do
      it 'generates report of invalid fa applicant relationships' do
        expect(subject.call(action_type: 'report').success?).to be_truthy
      end

      it 'generates reports with correct fa applicant relationships' do
        subject.call(action_type: 'report')
        file_path = Rails.root.join("invalid_fa_applicant_relationship_kinds_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
        expect(File.exist?(file_path)).to be_truthy

        csv_data = CSV.read(file_path, headers: true)
        expect(csv_data.length).to eq(2)

        row1 = csv_data[0]
        expect(row1['Primary Person Hbx ID']).to eq(primary.hbx_id)
        expect(row1['FA Application Hbx ID']).to eq(fa_application.hbx_id)
        expect(row1['FA Application Assistance Year']).to eq(fa_application.assistance_year.to_s)
        expect(row1['FA Application AASM State']).to eq(fa_application.aasm_state)
        expect(row1['FA Application Transfer ID']).to be_blank
        expect(row1['Applicant ID']).to eq(primary_applicant_id.to_s)
        expect(row1['Relative ID']).to eq(dependent1_applicant_id.to_s)
        expect(row1['Invalid Relationship Kind']).to eq('self')

        row2 = csv_data[1]
        expect(row2['Primary Person Hbx ID']).to eq(primary.hbx_id)
        expect(row2['FA Application Hbx ID']).to eq(fa_application.hbx_id)
        expect(row2['FA Application Assistance Year']).to eq(fa_application.assistance_year.to_s)
        expect(row2['FA Application AASM State']).to eq(fa_application.aasm_state)
        expect(row2['FA Application Transfer ID']).to be_blank
        expect(row2['Applicant ID']).to eq(dependent1_applicant_id.to_s)
        expect(row2['Relative ID']).to eq(dependent2_applicant_id.to_s)
        expect(row2['Invalid Relationship Kind']).to eq('other_relationship')
      end
    end
  end
end
