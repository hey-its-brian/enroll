# frozen_string_literal: true

module Eligibilities
  module V3
    # Exhibit is a source of information that acts as a proof to support an evidence (or a raised Data Matching Inconsistency).
    # Exhibit can be:
    #   - a document uploaded by the user that is verified by the admin
    #   - a call can be made to an external (DMV, IRS, SSA, etc) service to verify the evidence
    #   - admin can manually verify the evidence
    #   - self-attested by the user in some cases (for example, American Indian Status)
    class Exhibit
      include Mongoid::Document
      include Mongoid::Timestamps
      include ::HasDocument

      embedded_in :evidence, class_name: '::Eligibilities::V3::Evidence'
    end
  end
end
