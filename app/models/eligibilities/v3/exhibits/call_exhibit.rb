# frozen_string_literal: true

module Eligibilities
  module V3
    module Exhibits
      # CallExhibit is one type of exhibit that acts as a proof to support an evidence.
      # The system automatically calls an external service to verify the evidence.
      class CallExhibit < ::Eligibilities::V3::Exhibit
        include ::Eligibilities::V3::ExhibitUtils
      end
    end
  end
end
