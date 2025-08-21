# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::Families::RelocateEnrolledProducts, dbclean: :after_each do
  describe '#call' do
    context 'when:
      - qhp_application is enabled
      - with any params' do

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      end

      it 'returns a failure with an error message' do
        expect(subject.call({}).failure).to eq(
          'Relocation of Enrolled Products is not needed when QHP application feature is enabled.'
        )
      end
    end
  end
end
