# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::TaxForms::RegenerateTaxForm, type: :operation do
  subject { described_class.new }

  let(:user) { create(:user) }
  let(:person) { create(:person, :with_consumer_role) }
  let(:document) { create(:document, doc_identifier: BSON::ObjectId.new.to_s, documentable: person) }
  let(:valid_params) do
    {
      model: 'person',
      model_id: person.id.to_s,
      relation_id: document.id.to_s,
      relation: 'documents'
    }
  end
  let(:opts) { { params: valid_params, user: user } }

  describe '#call' do
    context 'when all operations succeed' do
      before do
        person.consumer_role.update(contact_method: ['Electronic'])
      end

      it 'returns success with inbox message' do
        result = subject.call(opts)

        expect(result).to be_success
        expect(result.success).to be_present
      end

      it 'processes the document successfully' do
        expect { subject.call(opts) }.not_to raise_error
      end
    end

    context 'when validation fails' do
      let(:invalid_params) { { model: '', model_id: '', relation_id: '' } }
      let(:invalid_opts) { { params: invalid_params, user: user } }

      it 'returns failure with validation errors' do
        result = subject.call(invalid_opts)

        expect(result).to be_failure
        expect(result.failure).to be_a(Hash)
      end
    end

    context 'when person does not exist' do
      let(:invalid_person_params) do
        {
          model: 'person',
          model_id: '999999999',
          relation_id: document.id.to_s
        }
      end
      let(:invalid_opts) { { params: invalid_person_params, user: user } }

      it 'returns failure' do
        result = subject.call(invalid_opts)

        expect(result).to be_failure
      end
    end

    context 'when document does not exist' do
      let(:invalid_document_params) do
        {
          model: 'person',
          model_id: person.id.to_s,
          relation_id: '999999999',
          relation: 'documents'
        }
      end
      let(:invalid_opts) { { params: invalid_document_params, user: user } }

      it 'returns failure with document error message' do
        result = subject.call(invalid_opts)

        expect(result).to be_failure
        expect(result.failure).to eq({ message: 'Unable to find Document' })
      end
    end
  end

  describe '#fetch_resource' do
    context 'when model is Person' do
      it 'returns the person successfully' do
        result = subject.send(:fetch_resource, valid_params)

        expect(result).to be_success
        expect(result.success).to eq(person)
      end
    end

    context 'when model does not exist' do
      let(:invalid_params) do
        {
          model: 'person',
          model_id: '999999999',
          relation_id: document.id.to_s
        }
      end

      it 'returns failure' do
        result = subject.send(:fetch_resource, invalid_params)

        expect(result).to be_failure
      end
    end
  end

  describe '#fetch_document' do
    context 'when document exists' do
      it 'returns success with document' do
        result = subject.send(:fetch_document, person, document.id.to_s)

        expect(result).to be_success
        expect(result.success).to eq(document)
      end
    end

    context 'when document does not exist' do
      it 'returns failure with error message' do
        result = subject.send(:fetch_document, person, '999999999')

        expect(result).to be_failure
        expect(result.failure).to eq({ message: 'Unable to find Document' })
      end
    end

    context 'when document belongs to different person' do
      let(:other_person) { create(:person) }
      let(:other_document) { create(:document, documentable: other_person) }

      it 'returns failure' do
        result = subject.send(:fetch_document, person, other_document.id.to_s)

        expect(result).to be_failure
        expect(result.failure).to eq({ message: 'Unable to find Document' })
      end
    end
  end

  describe '#generate_inbox_message' do
    let(:expected_payload) do
      {
        subjects: [{ id: person.hbx_id, type: "Person" }],
        file_name: "Resend tx form - #{document.title}",
        id: document.doc_identifier,
        file_content_type: "application/pdf"
      }
    end

    it 'generates inbox message with correct payload' do
      result = subject.send(:generate_inbox_message, person, document)

      expect(result).to be_success
    end
  end

  describe '#copy_to_s3' do
    context 'when resource is Person with consumer role and Paper contact method' do
      before do
        allow(::Operations::Documents::Copy).to receive(:call).and_return(Dry::Monads::Success(true))
        person.consumer_role.update(contact_method: ['Paper', 'Electronic'])
      end

      it 'performs S3 copy operation' do
        result = subject.send(:copy_to_s3, person, document, valid_params, user)

        expect(result).to be_success
      end
    end

    context 'when Person has no consumer role' do
      let(:person_without_consumer) { create(:person) }

      it 'returns nil without calling copy operation' do
        result = subject.send(:copy_to_s3, person_without_consumer, document, valid_params, user)

        expect(result.value!).to eq true
      end
    end

    context 'when Person does not have Paper contact method' do
      before do
        person.consumer_role.update(contact_method: ['Electronic'])
      end

      it 'returns nil without calling copy operation' do
        result = subject.send(:copy_to_s3, person, document, valid_params, user)

        expect(result.value!).to eq true
      end
    end
  end

  describe '#fetch_file_name' do
    context 'when document title contains Corrected' do
      let(:corrected_document) { create(:document, title: 'Corrected 1095-A Tax Form', documentable: person) }

      it 'returns corrected subject text' do
        result = subject.send(:fetch_file_name, corrected_document)

        expect(result).to eq('Your Requested Copy of Corrected 1095-A Tax Form')
      end
    end

    context 'when document title contains Void' do
      let(:void_document) { create(:document, title: 'Void 1095-A Tax Form', documentable: person) }

      it 'returns void subject text' do
        result = subject.send(:fetch_file_name, void_document)

        expect(result).to eq('Your Requested Copy of Voided 1095-A Tax Form')
      end
    end

    context 'when document title is original' do
      let(:original_document) { create(:document, title: '1095-A Tax Form', documentable: person) }

      it 'returns original subject text' do
        result = subject.send(:fetch_file_name, original_document)

        expect(result).to eq('Your Requested Copy of 1095-A Tax Form')
      end
    end
  end

  describe '#determine_notice_type' do
    it 'returns Corrected for title containing Corrected' do
      result = subject.send(:determine_notice_type, 'Corrected 1095-A')

      expect(result).to eq('Corrected')
    end

    it 'returns Void for title containing Void' do
      result = subject.send(:determine_notice_type, 'Void 1095-A')

      expect(result).to eq('Voided')
    end

    it 'returns nil for original title' do
      result = subject.send(:determine_notice_type, '1095-A Tax Form')

      expect(result).to be_nil
    end

    it 'is case insensitive for Corrected' do
      result = subject.send(:determine_notice_type, 'CORRECTED 1095-A')

      expect(result).to eq('Corrected')
    end

    it 'is case insensitive for Void' do
      result = subject.send(:determine_notice_type, 'void 1095-A')

      expect(result).to eq('Voided')
    end
  end
end
