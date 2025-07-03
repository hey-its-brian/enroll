# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::People::ValidateIdentityVerification, dbclean: :after_each do
  let(:operation) { described_class.new }
  let(:identity_response_code) { 'acc' }
  let(:person1) { FactoryBot.create(:person, :with_consumer_role) }
  let(:person2) { FactoryBot.create(:person, :with_consumer_role) }
  let(:user1) { FactoryBot.create(:user, person: person1, identity_response_code: identity_response_code) }
  let(:user2) { FactoryBot.create(:user, person: person2, identity_response_code: identity_response_code) }
  let(:csv_filename) { 'user_identity_validation_report.csv' }

  after do
    FileUtils.rm_f(csv_filename) if File.exist?(csv_filename)
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:params) do
        {
          type: 'report',
          identity_response_code: identity_response_code
        }
      end

      let(:user_data1) do
        {
          '_id' => person1.id.to_s,
          'identity_response_code' => 'acc',
          'created_at' => Time.now,
          'person_hbx_id' => person1.hbx_id,
          'consumer_created_at' => Time.now - 1.day,
          'identity_validation' => 'pending',
          'identity_update_reason' => nil,
          'application_validation' => 'pending',
          'application_update_reason' => nil
        }
      end

      let(:user_data2) do
        {
          '_id' => person2.id.to_s,
          'identity_response_code' => 'acc',
          'created_at' => Time.now,
          'person_hbx_id' => person2.hbx_id,
          'consumer_created_at' => Time.now - 2.days,
          'identity_validation' => 'rejected',
          'identity_update_reason' => 'Failed identity proofing',
          'application_validation' => 'rejected',
          'application_update_reason' => 'Failed application proofing'
        }
      end

      let(:users_data) { [user_data1, user_data2] }

      before do
        allow(operation).to receive(:fetch_users).and_return(Dry::Monads::Success(users_data))
        allow(operation).to receive(:create_report).and_call_original
        allow(operation).to receive(:update_identity_verification).and_return(Dry::Monads::Success())
      end

      it 'returns a success monad' do
        result = operation.call(params)
        expect(result).to be_success
        expect(result.value!).to eq('Report created successfully')
      end

      it 'creates a CSV file with the expected data' do
        operation.call(params)
        expect(File.exist?(csv_filename)).to be true

        csv_data = CSV.read(csv_filename)
        expect(csv_data[0]).to eq(Operations::People::ValidateIdentityVerification::REPORT_HEADERS)

        expect(csv_data[1][0]).to eq(user_data1['_id'])
        expect(csv_data[1][1]).to eq(user_data1['identity_response_code'])
        expect(csv_data[1][3]).to eq(user_data1['person_hbx_id'])
        expect(csv_data[1][5]).to eq(user_data1['identity_validation'])

        expect(csv_data[2][0]).to eq(user_data2['_id'])
        expect(csv_data[2][1]).to eq(user_data2['identity_response_code'])
        expect(csv_data[2][3]).to eq(user_data2['person_hbx_id'])
        expect(csv_data[2][5]).to eq(user_data2['identity_validation'])
        expect(csv_data[2][6]).to eq(user_data2['identity_update_reason'])
      end
    end

    context 'with update_identity_verification type' do
      let(:params) do
        {
          type: 'update_identity_verification',
          identity_response_code: identity_response_code
        }
      end

      before do
        person1.consumer_role.update_attributes!(identity_validation: 'pending')
        person2.consumer_role.update_attributes!(identity_validation: 'rejected')

        allow(operation).to receive(:fetch_users).and_return(
          Dry::Monads::Success([
            { '_id' => user1.id.to_s, 'person_hbx_id' => person1.hbx_id, 'identity_response_code' => 'acc' },
            { '_id' => user2.id.to_s, 'person_hbx_id' => person2.hbx_id, 'identity_response_code' => 'acc' }
          ])
        )

        allow(operation).to receive(:update_identity_verification).and_call_original
        allow(operation).to receive(:create_report).and_call_original
      end

      it 'updates identity validation for matching persons' do
        result = operation.call(params)
        expect(result).to be_success

        person1.reload
        person2.reload

        expect(person1.consumer_role.identity_validation).to eq('valid')
        expect(person2.consumer_role.identity_validation).to eq('valid')
      end

      it 'creates a CSV report of the updated users' do
        operation.call(params)
        expect(File.exist?(csv_filename)).to be true

        csv_data = CSV.read(csv_filename)
        expect(csv_data.size).to eq(3)

        user_ids_in_csv = csv_data.drop(1).map { |row| row[0] }
        expect(user_ids_in_csv).to include(user1.id.to_s)
        expect(user_ids_in_csv).to include(user2.id.to_s)
      end
    end

    context 'with invalid parameters' do
      it 'returns failure when params are blank' do
        result = operation.call(nil)
        expect(result).to be_failure
        expect(result.failure).to eq('Missing report parameters')
      end

      it 'returns failure when type is invalid' do
        result = operation.call(type: 'xyz', identity_response_code: 'acc')
        expect(result).to be_failure
        expect(result.failure).to eq('Invalid type')
      end
    end
  end
end
