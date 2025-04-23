# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Exports::Families::Eligibility::ExportFamilyEligibilityUnconditionallyCsv do
  let(:channel) { instance_double(Bunny::Channel) }
  let(:connection) { instance_double(Bunny::Session) }
  let(:queue) { instance_double(Bunny::Queue) }
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
  let(:properties) { instance_double(Bunny::MessageProperties) }
  let(:csv_file_path) { "redetermine_outstanding_families_eligibilities_report_unconditionally.csv" }
  let(:connection_proxy) { instance_double('EventSource::ConnectionProxy', connection_uri: 'amqp://localhost') }

  before do
    allow(channel).to receive(:connection).and_return(connection)
    allow(connection).to receive(:start)
    allow(connection).to receive(:create_channel).and_return(channel)
    allow(Bunny).to receive(:new).and_return(connection)
    connection_manager = instance_double('EventSource::ConnectionManager')
    allow(EventSource::ConnectionManager).to receive(:instance).and_return(connection_manager)
    allow(connection_manager).to receive(:find_connection)
      .with(protocol: :amqp, subscribe_operation_name: described_class.result_queue_name)
      .and_return(connection_proxy)
    allow(described_class).to receive(:connection_proxy).and_return(connection_proxy)
  end

  describe '.result_queue_name' do
    it 'returns the correct queue name' do
      expect(described_class.result_queue_name).to eq("on_enroll.enroll.migration_results")
    end
  end

  describe '.create_queue' do
    it 'creates a durable queue' do
      expect(channel).to receive(:queue).with(
        described_class.result_queue_name,
        durable: true
      ).and_return(queue)
      described_class.create_queue(channel)
    end
  end

  describe '.run' do
    let(:instance) { instance_double(described_class) }

    before do
      allow(described_class).to receive(:connection_uri).and_return("amqp://localhost")
      allow(Bunny).to receive(:new).with("amqp://localhost", heartbeat: 15).and_return(connection)
      allow(connection).to receive(:start)
      allow(connection).to receive(:create_channel).and_return(channel)
      allow(described_class).to receive(:create_queue).with(channel).and_return(queue)
      allow(described_class).to receive(:new).with(channel, queue).and_return(instance)
      allow(instance).to receive(:build)
    end

    it 'initializes and runs the export process' do
      described_class.run
      expect(connection).to have_received(:start)
      expect(connection).to have_received(:create_channel)
      expect(described_class).to have_received(:create_queue).with(channel)
      expect(described_class).to have_received(:new).with(channel, queue)
      expect(instance).to have_received(:build)
    end
  end

  describe '#run_records' do
    let(:payload) do
      {
        person_hbx_id: "123456",
        family_hbx_id: "789012",
        previous_determination_status: "eligible",
        previous_due_date: "2023-01-01",
        current_determination_status: "ineligible",
        current_due_date: "2023-12-31",
        message: "Status changed"
      }.to_json
    end

    let(:csv) { instance_double(CSV) }
    let(:instance) { described_class.new(channel, queue) }

    before do
      allow(queue).to receive(:pop).with(manual_ack: true)
                                   .and_return([delivery_info, properties, payload], nil)
      allow(csv).to receive(:<<)
    end

    it 'processes records and writes to CSV' do
      instance.run_records(csv)

      expect(csv).to have_received(:<<).with([
        "123456",
        "789012",
        "eligible",
        "2023-01-01",
        "ineligible",
        "2023-12-31",
        "Status changed"
      ])
    end
  end

  describe '#extract_data_row' do
    let(:data_payload) do
      {
        person_hbx_id: "123456",
        family_hbx_id: "789012",
        previous_determination_status: "eligible",
        previous_due_date: "2023-01-01",
        current_determination_status: "ineligible",
        current_due_date: "2023-12-31",
        message: "Status changed"
      }
    end

    it 'extracts data from payload into CSV row format' do
      instance = described_class.new(channel, queue)
      result = instance.send(:extract_data_row, data_payload)

      expect(result).to eq([
        "123456",
        "789012",
        "eligible",
        "2023-01-01",
        "ineligible",
        "2023-12-31",
        "Status changed"
      ])
    end
  end
end
