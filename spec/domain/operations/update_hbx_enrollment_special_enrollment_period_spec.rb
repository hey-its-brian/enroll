# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe Operations::UpdateHbxEnrollmentSpecialEnrollmentPeriodId, type: :model, dbclean: :after_each do

  let!(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:today) { Date.new(2025, 12, 12) }
  let(:year) { today.year }
  let(:yesterday) { today - 1.day }
  let(:tomorrow) { today + 1.day }

  subject(:operation) { described_class.new }

  before do
    allow(TimeKeeper).to receive(:date_of_record).and_return(today)
  end

  def create_enrollment(family_obj, created_at_date, state, kind, sep_id)
    FactoryBot.create(
      :hbx_enrollment,
      family: family_obj,
      household: family_obj.active_household,
      aasm_state: state,
      enrollment_kind: kind,
      special_enrollment_period_id: sep_id,
      created_at: created_at_date
    )
  end

  def create_sep(family_obj, start_on_date, end_on_date = nil, effective_on_date = start_on_date)
    FactoryBot.create(
      :special_enrollment_period,
      family: family_obj,
      start_on: start_on_date,
      end_on: end_on_date,
      effective_on: effective_on_date
    )
  end

  describe '#call' do
    context 'with invalid parameters' do
      it 'returns Failure if year is missing' do
        result = operation.call({ year: nil })
        expect(result.failure?).to be true
        expect(result.failure).to eq("Missing Year")
      end
    end

    context 'with valid parameters' do

      context 'when enrollments exist' do
        let!(:enrollment_with_direct_sep) do
          create_enrollment(family, today, 'coverage_selected', 'special_enrollment', nil)
        end
        let!(:direct_sep) { create_sep(family, yesterday, tomorrow) }

        let(:pred) do
          create_enrollment(family, yesterday - 1.day, 'coverage_terminated', 'special_enrollment', direct_sep.id)
        end

        let!(:enrollment_no_direct_sep_predecessor_has_sep) do
          create_enrollment(family, today, 'coverage_selected', 'special_enrollment', nil)
        end

        let!(:predecessor_sep) { create_sep(family, yesterday - 2.days, yesterday - 1.day) }

        let!(:pred_no_sep) do
          create_enrollment(family, yesterday - 5.days, 'coverage_terminated', 'special_enrollment', nil)
        end

        let!(:enrollment_no_sep_in_chain) do
          create_enrollment(family, yesterday - 4.days, 'coverage_selected', 'special_enrollment', nil)
        end

        let(:pred2) do
          create_enrollment(family, today - 10.days, 'coverage_terminated', 'special_enrollment', nil)
        end

        let(:pred1) do
          create_enrollment(family, today - 5.days, 'coverage_terminated', 'special_enrollment', nil)
        end

        let!(:enrollment_sep_on_predecessor_chain_link2) do
          create_enrollment(family, today - 5.days, 'coverage_selected', 'special_enrollment', nil)
        end

        let!(:deep_sep) { create_sep(family, today - 11.days, today - 9.days) }

        before do
          enrollment_no_direct_sep_predecessor_has_sep.update(predecessor_enrollment_id: pred.id)
          enrollment_no_sep_in_chain.update(predecessor_enrollment_id: pred_no_sep.id)
          pred1.update(predecessor_enrollment_id: pred2.id)
          enrollment_sep_on_predecessor_chain_link2.update(predecessor_enrollment_id: pred1.id)
        end

        it 'processes enrollments' do
          result = operation.call({ year: year })
          expect(result.success?).to be true
        end

        it "updates the enrollments with special enrollment period Ids" do
          operation.call({ year: year })
          expect(HbxEnrollment.where(:special_enrollment_period_id.ne => nil).count).to eq(6)
        end

        it 'generates a CSV file with the correct data' do
          result = operation.call({ year: year })
          expect(result.success?).to be true
          csv_file_name = result.success.split(': ').last
          csv_data = CSV.parse(File.read(csv_file_name))
          date = TimeKeeper.date_of_record.strftime("%Y_%m_%d")
          filename = "#{Rails.root}/updated_enrollments_special_enrollment_period_ids_#{date}.csv"
          expect(File.exist?(filename)).to be true

          expect(csv_data[0]).to eq(['Primary Hbx Id', 'Enrollment Hbx Id', 'Enrollment Kind', 'Enrollment State', 'Special Enrollment Period Id', 'Enrollment Predecessor Hbx Id'])

          row1 = csv_data.find { |row| row[1] == enrollment_with_direct_sep.hbx_id }
          expect(row1).not_to be_nil
          expect(row1[0]).to eq(family.primary_person.hbx_id)
          expect(row1[4]).to eq(direct_sep.id.to_s)
          expect(row1[5]).to be_empty

          row3 = csv_data.find { |row| row[1] == enrollment_no_sep_in_chain.hbx_id }
          expect(row3).not_to be_nil
          expect(row3[4]).to eq("No SEP Found")
          expect(row3[5]).to eq(enrollment_no_sep_in_chain.predecessor_enrollment.hbx_id)

          row4 = csv_data.find { |row| row[1] == enrollment_sep_on_predecessor_chain_link2.hbx_id }
          expect(row4).not_to be_nil
          expect(row4[4]).to eq(deep_sep.id.to_s)
          expect(row4[5]).to eq(enrollment_sep_on_predecessor_chain_link2.predecessor_enrollment.hbx_id)
        end
      end
    end
  end
end