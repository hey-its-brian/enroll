# frozen_string_literal: true

module Eligibilities
  module V3
    module Exhibits
      # UploadExhibit is one type of exhibit that acts as a proof to support an evidence.
      # User uploads a document that is verified by the admin.
      class UploadExhibit < ::Eligibilities::V3::Exhibit
        include ::Eligibilities::V3::ExhibitUtils
      end
    end
  end
end
