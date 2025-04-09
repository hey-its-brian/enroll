# frozen_string_literal: true

module Eligibilities
  module V3
    module Exhibits
      # AttestationExhibit is one type of exhibit that acts as a proof to support an evidence.
      # System allows self-atteststion for some evidences. User can attest the evidence by themselves.
      class AttestationExhibit < ::Eligibilities::V3::Exhibit
        include ::Eligibilities::V3::ExhibitUtils
      end
    end
  end
end
