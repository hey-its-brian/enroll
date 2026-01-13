# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::People::SsnTaken, type: :model, dbclean: :after_each do
  include Dry::Monads[:result]

  before :all do
    DatabaseCleaner.clean
  end

  let(:person) { FactoryBot.create(:person, :with_consumer_role, first_name: first_name, last_name: last_name, dob: dob, ssn: ssn, hbx_id: hbx_id) }
  let(:enabled) { true }
  let(:hbx_id) { 'hbx123456789' }
  let(:expected_param_result) { Success([:dob, :encrypted_ssn, :first_name, :last_name]) }

  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:person_match_policy).and_return(enabled)
    allow(subject).to receive(:fetch_expected_param_list).and_return(expected_param_result)
  end

  describe '#call' do
    context 'when expected_param_list includes:
      - dob,
      - encrypted_ssn,
      - first_name,
      - last_name
      ' do

      context 'when :person_match_policy is not enabled' do
        let(:enabled) { false }
        let(:params) { {} }
        let(:expected_param_result) { Failure('person_match_policy is disabled') }

        it 'returns a failure with an error message' do
          expect(subject.call(params).failure).to eq('person_match_policy is disabled')
        end
      end

      context 'when input params are invalid' do
        context 'when there are no params' do
          let(:params) { {} }

          it 'returns a failure with an error message' do
            expect(subject.call(params).failure).to eq('Missing required parameter: dob')
          end
        end

        context 'when there is only dob' do
          let(:params) { { dob: TimeKeeper.date_of_record } }

          it 'returns a failure with an error message' do
            expect(subject.call(params).failure).to eq('Missing required parameter: ssn')
          end
        end

        context 'when there are only dob and encrypted_ssn' do
          let(:params) { { dob: TimeKeeper.date_of_record, ssn: '123456789' } }

          it 'returns a failure with an error message' do
            expect(subject.call(params).failure).to eq('Missing required parameter: first_name')
          end
        end

        context 'when there are only dob, encrypted_ssn, and first_name' do
          let(:params) { { dob: TimeKeeper.date_of_record, ssn: '123456789', first_name: 'John' } }

          it 'returns a failure with an error message' do
            expect(subject.call(params).failure).to eq('Missing required parameter: last_name')
          end
        end

        context 'when there are all required params' do
          context 'when ssn is not valid, it is combination of strings, numbers, & special chars' do
            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '28db&^8786',
                first_name: 'John',
                last_name: 'Doe'
              }
            end

            it 'returns a failure with an error message' do
              expect(subject.call(params).failure).to eq('SSN is not valid.')
            end
          end

          context 'when ssn is not valid, it is combination invalid number of required numbers' do
            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '12345678',
                first_name: 'John',
                last_name: 'Doe'
              }
            end

            it 'returns a failure with an error message' do
              expect(subject.call(params).failure).to eq('SSN is not valid.')
            end
          end

          context 'when dob is not valid, it is not a date' do
            let(:params) do
              {
                dob: 'date',
                ssn: '123456789',
                first_name: 'John',
                last_name: 'Doe'
              }
            end

            it 'returns a failure with an error message' do
              expect(subject.call(params).failure).to eq('DOB is not valid.')
            end
          end

          context 'when first_name is not valid, it is not a string' do
            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '123456789',
                first_name: 23_876,
                last_name: 'Doe'
              }
            end

            it 'returns a failure with an error message' do
              expect(subject.call(params).failure).to eq('first_name is not valid.')
            end
          end

          context 'when last_name is not valid, it is not a string' do
            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '123456789',
                first_name: 'John',
                last_name: 37_645
              }
            end

            it 'returns a failure with an error message' do
              expect(subject.call(params).failure).to eq('last_name is not valid.')
            end
          end

          context 'when skipped_person is not valid, it is not a string' do
            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '123456789',
                first_name: 'John',
                last_name: 'Smith',
                skipped_person: 37_645
              }
            end

            it 'returns a failure with an error message' do
              expect(subject.call(params).failure).to eq('skipped_person is not valid.')
            end
          end

          context 'when all params are valid' do
            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '123456789',
                first_name: 'John',
                last_name: 'Doe'
              }
            end

            it 'returns a success with the params' do
              expect(subject.call(params).success).to eq(false)
            end
          end

          context 'when:
            - all params are valid
            - there is a person with the same ssn, dob, first_name, and last_name
            - but different cases
            ' do

            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '123456789',
                first_name: 'john',
                last_name: 'doe',
                skipped_person: '12345'
              }
            end

            let(:first_name) { params[:first_name] }
            let(:last_name) { params[:last_name] }
            let(:dob) { params[:dob] }
            let(:ssn) { params[:ssn] }

            it 'returns a success with the params' do
              person
              expect(subject.call(params).success).to eq(true)
            end
          end

          context 'when:
            - all params are valid
            - there is a person with the same ssn, dob, first_name, and last_name
            ' do

            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '123456789',
                first_name: 'John',
                last_name: 'Doe'
              }
            end
            let(:first_name) { params[:first_name] }
            let(:last_name) { params[:last_name] }
            let(:dob) { params[:dob] }
            let(:ssn) { params[:ssn] }

            it 'returns a success with the params' do
              person
              expect(subject.call(params).success).to eq(false)
            end
          end

          context 'when:
            - all params are valid
            - there is a person with the same ssn, dob, first_name, and a different last_name
            ' do

            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '123456789',
                first_name: 'John',
                last_name: 'Doe'
              }
            end
            let(:first_name) { params[:first_name] }
            let(:last_name) { 'DoeDoe' }
            let(:dob) { params[:dob] }
            let(:ssn) { params[:ssn] }

            it 'returns a success with the params' do
              person
              expect(subject.call(params).success).to eq(true)
            end
          end

          context 'when:
            - all params are valid
            - there is a person with different last_name but they are being skipped
            ' do

            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '123456789',
                first_name: 'John',
                last_name: 'Doe',
                skipped_person: hbx_id
              }
            end
            let(:first_name) { params[:first_name] }
            let(:last_name) { 'DoeDoe' }
            let(:dob) { params[:dob] }
            let(:ssn) { params[:ssn] }

            it 'returns a success with the params' do
              person
              expect(subject.call(params).success).to eq(false)
            end
          end

          context 'when:
            - all params are valid
            - there is a person with different last_name but they are not the same person who is being skipped
            ' do

            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '123456789',
                first_name: 'John',
                last_name: 'Doe',
                skipped_person: '123456789'
              }
            end
            let(:first_name) { params[:first_name] }
            let(:last_name) { 'DoeDoe' }
            let(:dob) { params[:dob] }
            let(:ssn) { params[:ssn] }

            it 'returns a success with the params' do
              person
              expect(subject.call(params).success).to eq(true)
            end
          end

          context 'when:
            - all params are valid
            - there is a person with the same ssn, dob, last_name, and a different first_name
            ' do

            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '123456789',
                first_name: 'John',
                last_name: 'Doe'
              }
            end
            let(:first_name) { 'JohnJohn' }
            let(:last_name) { params[:last_name] }
            let(:dob) { params[:dob] }
            let(:ssn) { params[:ssn] }

            it 'returns a success with the params' do
              person
              expect(subject.call(params).success).to eq(true)
            end
          end

          context 'when:
            - all params are valid
            - there is a person with the same ssn, first_name, last_name, and a different dob
            ' do

            let(:params) do
              {
                dob: TimeKeeper.date_of_record,
                ssn: '123456789',
                first_name: 'John',
                last_name: 'Doe'
              }
            end
            let(:first_name) { params[:first_name] }
            let(:last_name) { params[:last_name] }
            let(:dob) { TimeKeeper.date_of_record - 10.years }
            let(:ssn) { params[:ssn] }

            it 'returns a success with the params' do
              person
              expect(subject.call(params).success).to eq(true)
            end
          end
        end
      end
    end
  end
end
