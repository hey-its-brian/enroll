# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::DataFixes::CorrectInvalidApplicantRelationshipKinds, type: :model, dbclean: :after_each do
  before :all do
    DatabaseCleaner.clean

    file_path1 = Rails.root.join("invalid_applicant_relationship_kinds_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
    File.delete(file_path1) if File.exist?(file_path1)
    file_path2 = Rails.root.join("invalid_applicant_relationship_kinds_data_fix_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
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
      it 'fixes invalid applicant relationships' do
        expect(subject.call(action_type: 'data_fix').success?).to be_truthy
      end

      it 'fixes invalid FinancialAssistance applicant relationships with correct actions' do
        subject.call(action_type: 'data_fix')
        file_path = Rails.root.join("invalid_applicant_relationship_kinds_data_fix_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
        expect(File.exist?(file_path)).to be_truthy

        csv_data = CSV.read(file_path, headers: true)
        expect(csv_data.length).to eq(2)
        row1 = csv_data[0]
        expect(row1['Primary Person Hbx ID']).to eq(primary.hbx_id)
        expect(row1['Application Hbx ID']).to eq(fa_application.hbx_id)
        expect(row1['Application Type']).to eq('FinancialAssistance::Application')
        expect(row1['Application Assistance Year']).to eq(fa_application.assistance_year.to_s)
        expect(row1['Application State']).to eq(fa_application.aasm_state)
        expect(row1['Application Transfer ID']).to be_blank
        expect(row1['Applicant/Source ID']).to eq(primary_applicant_id.to_s)
        expect(row1['Relative ID']).to eq(dependent1_applicant_id.to_s)
        expect(row1['Invalid Relationship Kind']).to eq('self')
        expect(row1['Action Taken']).to eq('Destroyed relationship')

        row2 = csv_data[1]
        expect(row2['Primary Person Hbx ID']).to eq(primary.hbx_id)
        expect(row2['Application Hbx ID']).to eq(fa_application.hbx_id)
        expect(row2['Application Type']).to eq('FinancialAssistance::Application')
        expect(row2['Application Assistance Year']).to eq(fa_application.assistance_year.to_s)
        expect(row2['Application State']).to eq(fa_application.aasm_state)
        expect(row2['Application Transfer ID']).to be_blank
        expect(row2['Applicant/Source ID']).to eq(dependent1_applicant_id.to_s)
        expect(row2['Relative ID']).to eq(dependent2_applicant_id.to_s)
        expect(row2['Invalid Relationship Kind']).to eq('other_relationship')
        expect(row2['Action Taken']).to eq("Updated from other_relationship to unrelated")
      end
    end

    context 'when action_type is report' do
      it 'generates report of invalid applicant relationships' do
        expect(subject.call(action_type: 'report').success?).to be_truthy
      end

      it 'generates reports with correct FinancialAssistance applicant relationships' do
        subject.call(action_type: 'report')
        file_path = Rails.root.join("invalid_applicant_relationship_kinds_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
        expect(File.exist?(file_path)).to be_truthy

        csv_data = CSV.read(file_path, headers: true)
        expect(csv_data.length).to eq(2)

        row1 = csv_data[0]
        expect(row1['Primary Person Hbx ID']).to eq(primary.hbx_id)
        expect(row1['Application Hbx ID']).to eq(fa_application.hbx_id)
        expect(row1['Application Type']).to eq('FinancialAssistance::Application')
        expect(row1['Application Assistance Year']).to eq(fa_application.assistance_year.to_s)
        expect(row1['Application State']).to eq(fa_application.aasm_state)
        expect(row1['Application Transfer ID']).to be_blank
        expect(row1['Applicant/Source ID']).to eq(primary_applicant_id.to_s)
        expect(row1['Relative ID']).to eq(dependent1_applicant_id.to_s)
        expect(row1['Invalid Relationship Kind']).to eq('self')

        row2 = csv_data[1]
        expect(row2['Primary Person Hbx ID']).to eq(primary.hbx_id)
        expect(row2['Application Hbx ID']).to eq(fa_application.hbx_id)
        expect(row2['Application Type']).to eq('FinancialAssistance::Application')
        expect(row2['Application Assistance Year']).to eq(fa_application.assistance_year.to_s)
        expect(row2['Application State']).to eq(fa_application.aasm_state)
        expect(row2['Application Transfer ID']).to be_blank
        expect(row2['Applicant/Source ID']).to eq(dependent1_applicant_id.to_s)
        expect(row2['Relative ID']).to eq(dependent2_applicant_id.to_s)
        expect(row2['Invalid Relationship Kind']).to eq('other_relationship')
      end
    end

    context 'with IndividualMarket::Application' do
      let(:im_application) do
        FactoryBot.create(:individual_market_application, :with_primary,
                          family: family,
                          assistance_year: 2024,
                          origin: :user,
                          generation_reason: :manual)
      end
      let(:im_source_id) { BSON::ObjectId.new }
      let(:im_relative1_id) { BSON::ObjectId.new }
      let(:im_relative2_id) { BSON::ObjectId.new }

      let(:im_relationships) do
        im_application.relationships.build(
          {
            kind: 'self',
            source_id: im_source_id,
            relative_id: im_relative1_id
          }
        )

        im_application.relationships.build(
          {
            kind: 'other_relationship',
            source_id: im_relative1_id,
            relative_id: im_relative2_id
          }
        )
        im_application.save(validate: false)
      end

      before :each do
        im_relationships # Create IM relationships (FA relationships already created by outer before block)
      end

      it 'processes IndividualMarket applications with data_fix' do
        subject.call(action_type: 'data_fix', type: 'individual_market')
        file_path = Rails.root.join("invalid_applicant_relationship_kinds_data_fix_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")

        csv_data = CSV.read(file_path, headers: true)
        expect(csv_data.length).to eq(2)

        row1 = csv_data[0]
        expect(row1['Application Hbx ID']).to eq(im_application.hbx_id)
        expect(row1['Application Type']).to eq('IndividualMarket::Application')
        expect(row1['Application State']).to eq(im_application.current_state.to_s)
        expect(row1['Application Transfer ID']).to be_blank # CSV stores nil as empty string
        expect(row1['Applicant/Source ID']).to eq(im_source_id.to_s)
        expect(row1['Relative ID']).to eq(im_relative1_id.to_s)
        expect(row1['Invalid Relationship Kind']).to eq('self')
        expect(row1['Action Taken']).to eq('Destroyed relationship')

        row2 = csv_data[1]
        expect(row2['Application Type']).to eq('IndividualMarket::Application')
        expect(row2['Applicant/Source ID']).to eq(im_relative1_id.to_s)
        expect(row2['Invalid Relationship Kind']).to eq('other_relationship')
      end

      it 'processes IndividualMarket applications with report' do
        subject.call(action_type: 'report', type: 'individual_market')
        file_path = Rails.root.join("invalid_applicant_relationship_kinds_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")

        csv_data = CSV.read(file_path, headers: true)
        expect(csv_data.length).to eq(2)

        row1 = csv_data[0]
        expect(row1['Application Type']).to eq('IndividualMarket::Application')
        expect(row1['Applicant/Source ID']).to eq(im_source_id.to_s)
        expect(row1['Application State']).to eq(im_application.current_state.to_s)
        expect(row1['Application Transfer ID']).to be_blank # CSV stores nil as empty string
      end

      it 'processes both application types when type is both' do
        subject.call(action_type: 'report', type: 'both')
        file_path = Rails.root.join("invalid_applicant_relationship_kinds_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")

        csv_data = CSV.read(file_path, headers: true)
        expect(csv_data.length).to eq(4) # 2 FA + 2 IM

        app_types = csv_data.map { |row| row['Application Type'] }
        expect(app_types).to include('FinancialAssistance::Application')
        expect(app_types).to include('IndividualMarket::Application')
      end
    end

    context 'with type parameter' do
      it 'defaults to both when type is not provided' do
        result = subject.call(action_type: 'report')
        expect(result.success?).to be_truthy
      end

      it 'accepts individual_market type' do
        result = subject.call(action_type: 'report', type: 'individual_market')
        expect(result.success?).to be_truthy
      end

      it 'accepts financial_assistance type' do
        result = subject.call(action_type: 'report', type: 'financial_assistance')
        expect(result.success?).to be_truthy
      end

      it 'accepts both type' do
        result = subject.call(action_type: 'report', type: 'both')
        expect(result.success?).to be_truthy
      end

      it 'returns failure for invalid type' do
        result = subject.call(action_type: 'report', type: 'invalid_type')
        expect(result.failure?).to be_truthy
        expect(result.failure).to include("Invalid type: invalid_type")
      end
    end

    context 'with invalid action_type' do
      it 'returns failure for invalid action_type' do
        result = subject.call(action_type: 'invalid_action')
        expect(result.failure?).to be_truthy
        expect(result.failure).to include("Invalid action type: invalid_action")
      end
    end
  end
end
