# frozen_string_literal: true

module Eligibilities
  module V3
    module Exhibits
      # AdminExhibit is one type of exhibit that acts as a proof to support an evidence.
      # Admin automatically marks the evidence as verified.
      class AdminExhibit < ::Eligibilities::V3::Exhibit
        include ::Eligibilities::V3::ExhibitUtils
      end
    end
  end
end
