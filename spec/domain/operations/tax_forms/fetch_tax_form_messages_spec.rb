# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::TaxForms::FetchTaxFormMessages, type: :operation do
  subject { described_class.new }

  let(:person) { create(:person, :with_consumer_role) }
  let(:family) { create(:family, :with_primary_family_member, person: person) }
  let(:inbox) { create(:inbox, recipient: person) }

  before do
    person.update(inbox: inbox)
  end

  describe '#call' do
    context 'when all operations succeed' do
      let(:valid_params) do
        {
          person_id: person.id.to_s,
          family_id: family.id.to_s
        }
      end

      let!(:tax_form_message1) do
        create(:message,
               inbox: inbox,
               subject: 'Your 1095-A Health Coverage Tax Form',
               created_at: 2.days.ago)
      end

      let!(:tax_form_message2) do
        create(:message,
               inbox: inbox,
               subject: 'Corrected 1095-A Tax Form',
               created_at: 1.day.ago)
      end

      let!(:other_message) do
        create(:message,
               inbox: inbox,
               subject: 'Other notification',
               created_at: 3.days.ago)
      end

      it 'returns success with messages, person, and family' do
        result = subject.call(valid_params)

        expect(result).to be_success
        expect(result.success[:person]).to eq(person)
        expect(result.success[:family]).to eq(family)
        expect(result.success[:messages]).to include(tax_form_message1, tax_form_message2)
        expect(result.success[:messages]).not_to include(other_message)
      end

      it 'returns tax form messages ordered by created_at desc' do
        result = subject.call(valid_params)

        messages = result.success[:messages]
        expect(messages.first).to eq(tax_form_message2)
        expect(messages.last).to eq(tax_form_message1)
      end

      it 'only includes messages with tax form subjects' do
        result = subject.call(valid_params)

        messages = result.success[:messages]
        subjects = messages.map(&:subject)

        expect(subjects).to all(be_in(described_class::TAX_FORM_SUBJECTS))
      end
    end

    context 'when validation fails' do
      context 'with missing person_id' do
        let(:invalid_params) do
          {
            person_id: '',
            family_id: family.id.to_s
          }
        end

        it 'returns failure with validation error' do
          result = subject.call(invalid_params)
          expect(result).to be_failure
          expect(result.failure).to eq("Missing person_id")
        end
      end

      context 'with nil person_id' do
        let(:invalid_params) do
          {
            person_id: nil,
            family_id: family.id.to_s
          }
        end

        it 'returns failure with validation error' do
          result = subject.call(invalid_params)

          expect(result).to be_failure
          expect(result.failure).to eq("Missing person_id")
        end
      end

      context 'with missing family_id' do
        let(:invalid_params) do
          {
            family_id: '',
            person_id: person.id.to_s
          }
        end

        it 'returns failure with validation error' do
          result = subject.call(invalid_params)

          expect(result).to be_failure
          expect(result.failure).to eq("Missing family_id")
        end
      end

      context 'with nil family_id' do
        let(:invalid_params) do
          {
            family_id: nil,
            person_id: person.id.to_s
          }
        end

        it 'returns failure with validation error' do
          result = subject.call(invalid_params)

          expect(result).to be_failure
          expect(result.failure).to eq("Missing family_id")
        end
      end
    end

    context 'when person fetch fails' do
      let(:invalid_params) do
        {
          person_id: '999999999',
          family_id: family.id.to_s
        }
      end

      it 'returns failure' do
        result = subject.call(invalid_params)

        expect(result).to be_failure
      end
    end

    context 'when family fetch fails' do
      let(:invalid_params) do
        {
          person_id: person.id.to_s,
          family_id: '999999999'
        }
      end

      it 'returns failure' do
        result = subject.call(invalid_params)

        expect(result).to be_failure
      end
    end

    context 'when person has no tax form messages' do
      let(:valid_params) do
        {
          person_id: person.id.to_s,
          family_id: family.id.to_s
        }
      end

      let!(:other_message) do
        create(:message,
               inbox: inbox,
               subject: 'Other notification')
      end

      it 'returns success with empty messages collection' do
        result = subject.call(valid_params)

        expect(result).to be_success
        expect(result.success[:messages]).to be_empty
      end
    end
  end

  describe '#validate' do
    context 'with valid parameters' do
      let(:valid_params) do
        {
          person_id: person.id.to_s,
          family_id: family.id.to_s
        }
      end

      it 'returns success with params' do
        result = subject.send(:validate, valid_params)

        expect(result).to be_success
        expect(result.success).to eq(valid_params)
      end
    end

    context 'with invalid parameters' do
      it 'fails when person_id is blank' do
        result = subject.send(:validate, { person_id: '', family_id: family.id.to_s })

        expect(result).to be_failure
        expect(result.failure).to eq("Missing person_id")
      end

      it 'fails when family_id is blank' do
        result = subject.send(:validate, { person_id: person.id.to_s, family_id: '' })

        expect(result).to be_failure
        expect(result.failure).to eq("Missing family_id")
      end
    end
  end

  describe '#fetch_person' do
    context 'with valid person_id' do
      it 'returns success with person' do
        result = subject.send(:fetch_person, person.id.to_s)

        expect(result).to be_success
        expect(result.success).to eq(person)
      end
    end

    context 'with invalid person_id' do
      it 'returns failure' do
        result = subject.send(:fetch_person, '999999999')

        expect(result).to be_failure
      end
    end
  end

  describe '#fetch_family' do
    context 'with valid family_id' do
      it 'returns success with family' do
        result = subject.send(:fetch_family, family.id.to_s)

        expect(result).to be_success
        expect(result.success).to eq(family)
      end
    end
  end

  describe '#fetch_tax_form_messages' do
    let!(:tax_form_messages) do
      described_class::TAX_FORM_SUBJECTS.map.with_index do |subject, index|
        create(:message,
               inbox: inbox,
               subject: subject,
               created_at: index.days.ago)
      end
    end

    let!(:other_message) do
      create(:message,
             inbox: inbox,
             subject: 'Other notification')
    end

    it 'returns success with filtered and ordered messages' do
      result = subject.send(:fetch_tax_form_messages, person)

      expect(result).to be_success
      expect(result.success.count).to eq(3)
      expect(result.success).to include(*tax_form_messages)
      expect(result.success).not_to include(other_message)
    end

    it 'orders messages by created_at desc' do
      result = subject.send(:fetch_tax_form_messages, person)

      messages = result.success.to_a
      expect(messages.first.created_at).to be > messages.last.created_at
    end
  end

  describe 'TAX_FORM_SUBJECTS constant' do
    it 'contains expected tax form subjects' do
      expected_subjects = [
        'Corrected 1095-A Tax Form',
        'Void 1095-A Tax Form',
        'Your 1095-A Health Coverage Tax Form'
      ]

      expect(described_class::TAX_FORM_SUBJECTS).to match_array(expected_subjects)
    end

    it 'is frozen' do
      expect(described_class::TAX_FORM_SUBJECTS).to be_frozen
    end
  end
end
