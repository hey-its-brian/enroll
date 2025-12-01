# frozen_string_literal: true

require "rails_helper"
require File.join(Rails.root, "app", "data_migrations", "remove_duplicate_family_members")

describe RemoveDuplicateFamilyMembers, dbclean: :after_each do
  let(:given_task_name) { "remove_duplicate_family_members" }
  subject { RemoveDuplicateFamilyMembers.new(given_task_name, double(:current_scope => nil)) }

  describe "given a task name" do
    it "has the given task name" do
      expect(subject.name).to eql given_task_name
    end
  end

  describe "#parse_csv_ids" do
    it "returns array of trimmed ids" do
      expect(subject.parse_csv_ids("123, 345 ,235")).to eq(%w[123 345 235])
    end

    it "removes empty entries" do
      expect(subject.parse_csv_ids("123,, ,345")).to eq(%w[123 345])
    end

    it "returns empty array for blank or nil" do
      expect(subject.parse_csv_ids(nil)).to eq([])
      expect(subject.parse_csv_ids("")).to eq([])
      expect(subject.parse_csv_ids("   ")).to eq([])
    end
  end

  describe "#parse_ids_from_csv" do
    let(:csv_path) { "#{Rails.root}/spec/test_data/remove_duplicate_family_members_ids.csv" }

    before do
      FileUtils.mkdir_p(File.dirname(csv_path))
    end

    after do
      FileUtils.rm_f(csv_path)
    end

    it "raises when file does not exist" do
      expect { subject.parse_ids_from_csv("missing.csv") }
        .to raise_error(ArgumentError, /CSV file not found/)
    end

    it "reads IDs from a headerless CSV (first column)" do
      File.write(csv_path, "123\n345\n\n235\n")
      expect(subject.parse_ids_from_csv(csv_path)).to match_array(%w[123 345 235])
    end

    it "reads IDs from a CSV with hbx_id header" do
      File.write(csv_path, "hbx_id,other\n123,x\n345,y\n")
      expect(subject.parse_ids_from_csv(csv_path)).to match_array(%w[123 345])
    end

    it "deduplicates IDs from file" do
      File.write(csv_path, "hbx_id\n123\n123\n")
      expect(subject.parse_ids_from_csv(csv_path)).to eq(%w[123])
    end
  end

  describe "#migrate" do
    def create_duplicate_family_member(family, person, created_at_offset: 5.minutes)
      base_member = family.family_members.first
      dup_fm = FamilyMember.new(
        family: family,
        person: person,
        is_primary_applicant: false,
        created_at: base_member.created_at + created_at_offset
      )
      dup_fm.save(validate: false)
      dup_fm
    end

    context "when no hbx_ids and no csv_file are provided" do
      it "raises an error" do
        expect { subject.migrate(nil, nil) }
          .to raise_error(ArgumentError, /No valid HBX IDs/)
      end
    end

    context "when provided valid HBX IDs with duplicates via inline hbx_ids" do
      let(:person)  { FactoryBot.create(:person) }
      let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

      let!(:dup1) { family.family_members.first }
      let!(:dup2) { create_duplicate_family_member(family, person, created_at_offset: 5.minutes) }

      it "removes the newest duplicate" do
        expect(family.family_members.count).to eq(2)

        expect { subject.migrate(person.hbx_id, nil) }
          .to output(/Removed duplicate family_member/).to_stdout

        expect(family.reload.family_members.count).to eq(1)
      end
    end

    context "when family has no duplicates" do
      let(:person)  { FactoryBot.create(:person) }
      let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

      it "outputs no-duplicates message" do
        expect(family.family_members.count).to eq(1)

        expect { subject.migrate(person.hbx_id, nil) }
          .to output(/No duplicates/).to_stdout
      end
    end

    context "when Person record is missing" do
      it "prints missing person message" do
        expect { subject.migrate("nonexistent-hbx", nil) }
          .to output(/No Person found for HBX ID: nonexistent-hbx/).to_stdout
      end
    end

    context "when unexpected error occurs during lookup" do
      before do
        allow(Person).to receive(:where).and_raise(StandardError, "DB error")
      end

      it "catches and prints the error" do
        expect { subject.migrate("123", nil) }
          .to output(/Unexpected Error: DB error/).to_stdout
      end
    end

    context "when using ENV hbx_ids" do
      let(:person)  { FactoryBot.create(:person) }
      let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
      let!(:dup1)   { family.family_members.first }
      let!(:dup2)   { create_duplicate_family_member(family, person, created_at_offset: 5.minutes) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("hbx_ids").and_return(person.hbx_id)
        allow(ENV).to receive(:[]).with("csv_file").and_return(nil)
      end

      it "reads HBX IDs from ENV" do
        expect { subject.migrate }
          .to output(/HBX IDs processed: 1/).to_stdout

        expect(family.reload.family_members.count).to eq(1)
      end
    end

    context "when provided IDs via csv_file only" do
      let(:csv_path) { "#{Rails.root}/spec/test_data/remove_duplicate_family_members_ids.csv" }

      before do
        FileUtils.mkdir_p(File.dirname(csv_path))
        File.write(csv_path, "#{person.hbx_id}\n")
      end

      after do
        FileUtils.rm_f(csv_path)
      end

      let(:person)  { FactoryBot.create(:person) }
      let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
      let!(:dup1)   { family.family_members.first }
      let!(:dup2)   { create_duplicate_family_member(family, person, created_at_offset: 5.minutes) }

      it "removes duplicates based on IDs from file" do
        expect(family.family_members.count).to eq(2)

        expect { subject.migrate(nil, csv_path) }
          .to output(/Removed duplicate family_member/).to_stdout

        expect(family.reload.family_members.count).to eq(1)
      end
    end

    context "when using ENV csv_file only" do
      let(:csv_path) { "#{Rails.root}/spec/test_data/remove_duplicate_family_members_ids_env.csv" }

      before do
        FileUtils.mkdir_p(File.dirname(csv_path))
        File.write(csv_path, "#{person.hbx_id}\n")

        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("hbx_ids").and_return(nil)
        allow(ENV).to receive(:[]).with("csv_file").and_return(csv_path)
      end

      after do
        FileUtils.rm_f(csv_path)
      end

      let(:person)  { FactoryBot.create(:person) }
      let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
      let!(:dup1)   { family.family_members.first }
      let!(:dup2)   { create_duplicate_family_member(family, person, created_at_offset: 5.minutes) }

      it "reads IDs from ENV csv_file and processes them" do
        expect(family.family_members.count).to eq(2)

        expect { subject.migrate }
          .to output(/HBX IDs processed: 1/).to_stdout

        expect(family.reload.family_members.count).to eq(1)
      end
    end

    context "when IDs are provided in both hbx_ids and csv_file" do
      let(:csv_path) { "#{Rails.root}/spec/test_data/remove_duplicate_family_members_ids_both.csv" }

      before do
        FileUtils.mkdir_p(File.dirname(csv_path))
        # file: person1 and person2; inline: person2 and person3
        File.write(csv_path, "#{person1.hbx_id}\n#{person2.hbx_id}\n")
      end

      after do
        FileUtils.rm_f(csv_path)
      end

      let(:person1)  { FactoryBot.create(:person) }
      let(:person2)  { FactoryBot.create(:person) }
      let(:person3)  { FactoryBot.create(:person) }

      let!(:family1) { FactoryBot.create(:family, :with_primary_family_member, person: person1) }
      let!(:family2) { FactoryBot.create(:family, :with_primary_family_member, person: person2) }
      let!(:family3) { FactoryBot.create(:family, :with_primary_family_member, person: person3) }

      let!(:dup1_1) { family1.family_members.first }
      let!(:dup1_2) { create_duplicate_family_member(family1, person1, created_at_offset: 5.minutes) }

      let!(:dup2_1) { family2.family_members.first }
      let!(:dup2_2) { create_duplicate_family_member(family2, person2, created_at_offset: 10.minutes) }

      it "processes the union of IDs without double-processing duplicates" do
        hbx_ids_csv = [person2.hbx_id, person3.hbx_id].join(",")

        expect(family1.family_members.count).to eq(2)
        expect(family2.family_members.count).to eq(2)
        expect(family3.family_members.count).to eq(1)

        expect { subject.migrate(hbx_ids_csv, csv_path) }
          .to output(/HBX IDs processed: 3/).to_stdout

        expect(family1.reload.family_members.count).to eq(1)
        expect(family2.reload.family_members.count).to eq(1)
        expect(family3.reload.family_members.count).to eq(1)
      end
    end
  end
end
