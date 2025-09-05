# frozen_string_literal: true

require 'rails_helper'
require 'csv'
require "#{Rails.root}/app/domain/operations/remove_duplicate_faa_relationships"

RSpec.describe Operations::RemoveDuplicateFaaRelationships, type: :model, dbclean: :after_each do
  subject(:operation) { described_class.new }

  let(:year) { TimeKeeper.date_of_record.year }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member) }
  let(:primary_applicant) { FactoryBot.create(:financial_assistance_applicant, is_primary_applicant: true, family_member_id: family.primary_applicant.id) }
  let(:relative_applicant) { FactoryBot.create(:financial_assistance_applicant, family_member_id: family.family_members.last.id) }

  let!(:application_without_duplicates) do
    FactoryBot.create(
      :financial_assistance_application,
      family_id: family.id,
      aasm_state: 'draft',
      effective_date: TimeKeeper.date_of_record.beginning_of_year - 1.day
    )
  end

  let!(:application_with_duplicates) do
    FactoryBot.create(
      :financial_assistance_application,
      family_id: family.id,
      aasm_state: 'draft',
      effective_date: TimeKeeper.date_of_record.beginning_of_year,
      applicants: [primary_applicant, relative_applicant]
    )
  end

  before do
    application_with_duplicates.relationships.create!(applicant_id: primary_applicant.id, relative_id: relative_applicant.id, kind: 'spouse')
    application_with_duplicates.relationships.create!(applicant_id: primary_applicant.id, relative_id: relative_applicant.id, kind: 'spouse')
  end

  describe '#call' do

    before do
      allow(TimeKeeper).to receive(:date_of_record).and_return(TimeKeeper.date_of_record)
    end

    it 'removes the duplicate relationship from the application' do
      expect(application_with_duplicates.relationships.count).to eq(2)
      operation.call({ year: year })
      application_with_duplicates.reload
      expect(application_with_duplicates.relationships.count).to eq(1)
    end

    it 'writes the correct data to the CSV file' do
      operation.call({ year: year })
      date = TimeKeeper.date_of_record.strftime("%Y_%m_%d")
      filename = Rails.root.join("removed_duplicate_faa_relationships_#{date}.csv")
      csv_content = CSV.parse(File.read(filename))

      expect(csv_content[0]).to eq(['Primary Person Hbx Id', 'Application Hbx Id', 'Duplicate Relationship Kind', 'Duplicate Relationship Relative Id', 'Created At'])
      expect(csv_content[1][0]).to eq(family.primary_person.hbx_id)
      expect(csv_content[1][1]).to eq(application_with_duplicates.hbx_id)
      expect(csv_content[1][2]).to eq('spouse')
    end

    it 'returns a success message with the correct count' do
      result = operation.send(:remove_duplicate_relationships, [application_with_duplicates])
      expect(result).to be_a(Dry::Monads::Result::Success)
      expect(result.value!).to include("Successfully removed 1 duplicate relationships")
    end
  end
end