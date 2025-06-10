# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Validators::Sbm::FilteredApplicationIndexRequestContract do
  subject { described_class.new }

  let(:valid_bson_id) { BSON::ObjectId.new }

  describe 'validations' do
    context 'when params are valid' do
      let(:valid_params) do
        {
          family_id: valid_bson_id
        }
      end

      let(:valid_params_with_filter) do
        {
          family_id: valid_bson_id,
          filter_year: 2023
        }
      end

      it 'is valid without filter_year' do
        result = subject.call(valid_params)
        expect(result).to be_success
        expect(result.errors).to be_empty
      end

      it 'is valid with filter_year' do
        result = subject.call(valid_params_with_filter)
        expect(result).to be_success
        expect(result.errors).to be_empty
      end
    end

    context 'when params are invalid' do
      it 'is invalid without family_id' do
        result = subject.call({})
        expect(result).to be_failure
        expect(result.errors[:family_id]).to include('is missing')
      end

      it 'is invalid with non-integer filter_year' do
        result = subject.call(family_id: valid_bson_id, filter_year: 'not-an-integer')
        expect(result).to be_failure
        expect(result.errors[:filter_year]).to include('must be an integer')
      end
    end
  end
end
