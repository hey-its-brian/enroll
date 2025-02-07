# frozen_string_literal: true

require "rails_helper"
require File.join(Rails.root, "app", "data_migrations", "fix_atp_outbound_verification_codes")

describe FixAtpOutboundVerificationCodes, dbclean: :after_each do
  let(:given_task_name) { "fix_atp_outbound_verification_codes" }
  subject { FixAtpOutboundVerificationCodes.new(given_task_name, double(:current_scope => nil)) }

  describe "given a task name" do
    it "has the given task name" do
      expect(subject.name).to eql given_task_name
    end
  end

  describe "#parse_array_format" do
    context "with valid input" do
      it "parses single-quoted array format" do
        input = "['id1', 'id2', 'id3']"
        expect(subject.parse_array_format(input)).to eq(['id1', 'id2', 'id3'])
      end

      it "parses double-quoted array format" do
        input = '["id1", "id2", "id3"]'
        expect(subject.parse_array_format(input)).to eq(['id1', 'id2', 'id3'])
      end

      it "handles whitespace" do
        input = "[  'id1' ,  'id2'  , 'id3'  ]"
        expect(subject.parse_array_format(input)).to eq(['id1', 'id2', 'id3'])
      end
    end

    context "with invalid input" do
      it "raises error for non-array format" do
        expect { subject.parse_array_format("not an array") }.to raise_error(ArgumentError, /No valid HBX IDs found/)
      end

      it "raises error for malformed array" do
        expect { subject.parse_array_format("[id1, id2]") }.to raise_error(ArgumentError, /No valid HBX IDs found/)
      end
    end
  end

  describe "#migrate" do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:user) { FactoryBot.create(:user, person: person) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: 'renewal_draft') }
    let(:input_file) { "#{Rails.root}/spec/test_data/fix_atp_outbound_verification_codes_test.txt" }
    let(:hbx_ids) { ["app1", "app2", "app3"] }

    before do
      # Create test file with HBX IDs
      File.write(input_file, "['#{hbx_ids.join("', '")}']")
      allow(ENV).to receive(:[]).and_return(nil)
    end

    after do
      FileUtils.rm_f(input_file)
    end

    context "with valid input file" do
      before do
        hbx_ids.each do |id|
          allow(FinancialAssistance::Application).to receive(:find_by).with(hbx_id: id).and_return(application)
          allow(application).to receive(:transfer_account).and_return(double(success?: false))
        end
      end

      it "processes applications and reports failures" do
        expect { subject.migrate(input_file) }.to output(/Partial resubmission of applications completed/).to_stdout
      end
    end

    context "with invalid input file path" do
      it "raises an error for non-existent file" do
        expect { subject.migrate("nonexistent.txt") }.to raise_error(ArgumentError, /Input must be a path to an existing text file/)
      end
    end

    context "with empty input file" do
      before do
        File.write(input_file, "[]")
      end

      it "raises an error for empty HBX IDs" do
        expect { subject.migrate(input_file) }.to raise_error(ArgumentError, /No valid HBX IDs found/)
      end
    end

    context "with malformed input file" do
      before do
        File.write(input_file, "not an array")
      end

      it "raises error for invalid format" do
        expect { subject.migrate(input_file) }.to raise_error(ArgumentError, /No valid HBX IDs found/)
      end
    end

    context "when application transfer succeeds" do
      before do
        hbx_ids.each do |id|
          allow(FinancialAssistance::Application).to receive(:find_by).with(hbx_id: id).and_return(application)
          allow(application).to receive(:transfer_account).and_return(double(success?: true))
        end
      end

      it "reports success" do
        expect { subject.migrate(input_file) }.to output(/Successfully resubmitted all applications/).to_stdout
      end
    end

    context "when database error occurs" do
      before do
        allow(FinancialAssistance::Application).to receive(:find_by).and_raise(StandardError, "Database error")
      end

      it "handles the error gracefully" do
        expect { subject.migrate(input_file) }.to output(/Error: Database error/).to_stdout
      end
    end

    context "when using ENV variable" do
      before do
        allow(ENV).to receive(:[]).with('text_file').and_return(input_file)
        allow(FinancialAssistance::Application).to receive(:find_by).and_return(application)
        allow(application).to receive(:transfer_account).and_return(double(success?: true))
      end

      it "reads file path from ENV" do
        expect { subject.migrate }.to output(/Successfully resubmitted all applications/).to_stdout
      end
    end
  end
end
