# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ResourceRegistryHelper, type: :helper do
  describe '#qhp_application_feature_enabled?' do
    context 'when qhp_application feature is enabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      end

      it 'returns true' do
        expect(helper.qhp_application_feature_enabled?).to be true
      end
    end

    context 'when qhp_application feature is not enabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(false)
      end

      it 'returns false' do
        expect(helper.qhp_application_feature_enabled?).to be false
      end
    end
  end
end
