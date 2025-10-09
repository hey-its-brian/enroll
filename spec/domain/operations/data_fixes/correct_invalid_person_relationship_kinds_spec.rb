# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::DataFixes::CorrectInvalidPersonRelationshipKinds, type: :model, dbclean: :after_each do
  before :all do
    DatabaseCleaner.clean

    file_path1 = Rails.root.join("invalid_person_relationship_kinds_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
    File.delete(file_path1) if File.exist?(file_path1)
    file_path2 = Rails.root.join("invalid_person_relationship_kinds_data_fix_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
    File.delete(file_path2) if File.exist?(file_path2)
  end

  let(:primary1) do
    per = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
    per.person_relationships.build(kind: 'self', relative_id: per.id)
    per.save
    per
  end
  let(:primary2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:primary3) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }

  let(:dependent2a) do
    per = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
    primary2.ensure_relationship_with(per, 'other_relationship')
    per
  end

  let(:dependent3a) do
    per = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
    primary3.ensure_relationship_with(per, 'spouse')
    per
  end

  before :each do
    primary1
    dependent2a
    dependent3a
  end

  describe '#call' do
    context 'when action_type is data_fix' do
      it 'fixes invalid person relationships' do
        expect(subject.call(action_type: 'data_fix').success?).to be_truthy
      end

      it 'fixes invalid person relationships with correct actions' do
        subject.call(action_type: 'data_fix')
        file_path = Rails.root.join("invalid_person_relationship_kinds_data_fix_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
        expect(File.exist?(file_path)).to be_truthy

        csv_data = CSV.read(file_path, headers: true)
        expect(csv_data.length).to eq(2)

        row1 = csv_data[0]
        expect(row1['Primary Person Hbx ID']).to eq(primary1.hbx_id)
        expect(row1['Dependent Person Hbx ID']).to eq(primary1.hbx_id)
        expect(row1['Invalid Relationship Kind']).to eq('self')
        expect(row1['Action Taken']).to eq('Destroyed relationship')

        row2 = csv_data[1]
        expect(row2['Primary Person Hbx ID']).to eq(primary2.hbx_id)
        expect(row2['Dependent Person Hbx ID']).to eq(dependent2a.hbx_id)
        expect(row2['Invalid Relationship Kind']).to eq('unrelated')
        expect(row2['Action Taken']).to eq("Updated from other_relationship to unrelated")
      end
    end

    context 'when action_type is report' do
      it 'generates report of invalid person relationships' do
        expect(subject.call(action_type: 'report').success?).to be_truthy
      end

      it 'generates reports with correct person relationships' do
        subject.call(action_type: 'report')
        file_path = Rails.root.join("invalid_person_relationship_kinds_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
        expect(File.exist?(file_path)).to be_truthy

        csv_data = CSV.read(file_path, headers: true)
        expect(csv_data.length).to eq(2)

        row1 = csv_data[0]
        expect(row1['Primary Person Hbx ID']).to eq(primary1.hbx_id)
        expect(row1['Dependent Person Hbx ID']).to eq(primary1.hbx_id)
        expect(row1['Invalid Relationship Kind']).to eq('self')

        row2 = csv_data[1]
        expect(row2['Primary Person Hbx ID']).to eq(primary2.hbx_id)
        expect(row2['Dependent Person Hbx ID']).to eq(dependent2a.hbx_id)
        expect(row2['Invalid Relationship Kind']).to eq('other_relationship')
      end
    end
  end
end
