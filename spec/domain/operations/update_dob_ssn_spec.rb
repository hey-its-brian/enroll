# frozen_string_literal: true

RSpec.describe Operations::UpdateDobSsn, type: :model, dbclean: :after_each do
  let!(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

  it 'should be a container-ready operation' do
    expect(subject.respond_to?(:call)).to be_truthy
  end

  context 'with correct arguments' do
    let(:test_params) do
      { person: { person_id: person.id.to_s,
                  dob: "#{TimeKeeper.date_of_record.year}-01-01",
                  ssn: '789-83-4231',
                  pid: person.id.to_s,
                  family_actions_id: 'family_actions_238764'}, jq_datepicker_ignore_person: { dob: "01/01/#{TimeKeeper.date_of_record.year}" }}
    end

    let(:no_ssn_test_params) do
      { person: { person_id: person.id.to_s,
                  dob: "#{TimeKeeper.date_of_record.year}-01-01",
                  ssn: '',
                  pid: person.id.to_s,
                  family_actions_id: 'family_actions_238764'}, jq_datepicker_ignore_person: { dob: "01/01/#{TimeKeeper.date_of_record.year}" }}
    end

    context 'success' do
      before do
        person.consumer_role.update_attributes!(active_vlp_document_id: person.consumer_role.vlp_documents.first.id)
        @result = subject.call(person_id: person.id.to_s, params: test_params, current_user: 'c_user', ssn_require: false)
      end

      it 'should return success' do
        expect(@result).to be_a Dry::Monads::Result::Success
      end

      it 'should return success' do
        expect(@result.success).to eq([nil, nil])
      end
    end

    context 'success' do
      before do
        person.consumer_role.update_attributes!(active_vlp_document_id: person.consumer_role.vlp_documents.first.id)
        @result = subject.call(person_id: person.id.to_s, params: no_ssn_test_params, current_user: 'c_user', ssn_require: false)
      end

      it 'should return success' do
        expect(@result).to be_a Dry::Monads::Result::Success
      end

      it 'should return success' do
        expect(@result.success).to eq([nil, nil])
        person.reload
        expect(person.no_ssn).to eq "1"
      end
    end

    context 'failure' do
      before do
        @result = subject.call(person_id: 'person_id', params: test_params, current_user: 'c_user', ssn_require: false)
      end

      it 'should return Failure' do
        expect(@result.failure).to eq([{person: ['Person not found']}, nil])
      end
    end
  end

  context '#call update_ssn' do
    let(:valid_ssn) { '789834231' }
    let(:valid_dob) { "#{TimeKeeper.date_of_record.year}-01-01" }
    let(:dob_param) { "01/01/#{TimeKeeper.date_of_record.year}" }
    let(:current_user) { double('User') }

    let(:params_with_ssn) do
      {
        person: {
          pid: person.id.to_s,
          ssn: valid_ssn,
          dob: valid_dob
        },
        jq_datepicker_ignore_person: {
          dob: dob_param
        }
      }
    end

    let(:params_without_ssn) do
      {
        person: {
          pid: person.id.to_s,
          ssn: '',
          dob: valid_dob
        },
        jq_datepicker_ignore_person: {
          dob: dob_param
        }
      }
    end

    context 'when person exists' do
      context 'and SSN is provided' do
        it 'updates SSN and resets no_ssn to "0"' do
          result = subject.call(person_id: person.id.to_s, params: params_with_ssn, current_user: current_user, ssn_require: false)
          expect(result).to be_success
          person.reload
          expect(person.ssn).to eq valid_ssn
          expect(person.no_ssn).to eq '0'
          expect(person.dob.to_date).to eq Date.strptime(dob_param, '%m/%d/%Y')
        end
      end

      context 'and SSN is blank' do
        it 'sets no_ssn to "1"' do
          result = subject.call(person_id: person.id.to_s, params: params_without_ssn, current_user: current_user, ssn_require: false)
          expect(result).to be_success
          person.reload
          expect(person.ssn).to be_nil.or eq('')
          expect(person.no_ssn).to eq '1'
          expect(person.dob.to_date).to eq Date.strptime(dob_param, '%m/%d/%Y')
        end
      end
    end


    context 'when person does not exist' do
      it 'returns failure with person not found error' do
        result = subject.call(person_id: 'nonexistent_id', params: params_with_ssn, current_user: current_user, ssn_require: false)
        expect(result).to be_failure
        expect(result.failure).to eq([{person: ['Person not found']}, nil])
      end
    end
  end
end
