# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'default qhp application client specific configurations' do

  describe 'qhp_application' do
    context 'for default value' do
      it 'returns default value false' do
        expect(
          EnrollRegistry.feature_enabled?(:qhp_application)
        ).to be_falsey
      end
    end
  end
end
