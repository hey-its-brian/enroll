# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Exports::GenerateReport do

  let(:channel) { instance_double(Bunny::Channel) }
  let(:connection) { instance_double(Bunny::Session) }
  let(:queue) { instance_double(Bunny::Queue) }
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
  let(:properties) { instance_double(Bunny::MessageProperties) }
  let(:connection_proxy) { instance_double('EventSource::ConnectionProxy', connection_uri: 'amqp://localhost') }
  let(:file_name) { 'test_export.csv' }
  let(:headers) { ['Header1', 'Header2'] }
  let(:rows) { [['Value1', 'Value2']] }
  let(:payload) do
    {
      headers: headers,
      rows: rows,
      csv_file_name: file_name
    }.to_json
  end
  let(:instance) { described_class.new(channel, queue) }

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
      expect(described_class.result_queue_name).to eq('on_enroll.enroll.migration_results')
    end
  end

  describe '#build' do
    context 'when queue has messages' do
      before do
        allow(queue).to receive(:message_count).and_return(1)
        allow(queue).to receive(:channel).and_return(channel)
        allow(delivery_info).to receive(:delivery_tag).and_return('tag1')
        message_payload = {
          headers: headers,
          rows: rows,
          csv_file_name: file_name
        }.to_json

        allow(queue).to receive(:pop).and_return(
          [delivery_info, properties, message_payload],
          [nil, nil, nil]
        )

        allow(File).to receive(:exist?).with(anything).and_return(false)
        allow(FileUtils).to receive(:touch).with(anything)
        allow(File).to receive(:write).with(anything, anything)
        allow(channel).to receive(:ack)
      end

      it 'processes messages and generates CSV' do
        expect { instance.build }.not_to raise_error
        expect(File).to have_received(:write).with(file_name, anything)
      end
    end
  end
end