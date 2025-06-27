# frozen_string_literal: true

require 'rails_helper'
# require Rails.root.join('spec/shared_contexts/valid_cv3_application_setup.rb')

RSpec.describe Operations::Fdsh::BuildAndValidateUqhpApplicationPayload, dbclean: :after_each do
  # include_context "valid cv3 application setup"
  let(:application) { FactoryBot.create(:individual_market_application, :with_primary, submitted_at: Time.current) }

  describe '#call' do
    context 'when all validation rules pass' do
      it 'returns a Success result' do
        result = described_class.new.call(application)
        expect(result).to be_success
      end
    end

    context 'with a malformed cv3' do
      before do
        allow(application).to receive(:applicants).and_return(nil)
      end

      it 'raises an error' do
        result = described_class.new.call(application)

        expect(result).to be_failure
      end
    end
  end
end
