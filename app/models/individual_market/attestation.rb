# frozen_string_literal: true

module IndividualMarket
  # Represents a collection of attestations made by an applicant during the enrollment process
  #
  # @note This model stores information about all the signatures and agreements the account holder
  #   has provided, including authorizations for renewals, enrollment confirmations,
  #   and verification of provided information.
  #
  # @example Creating an attestation for an application
  #   application = IndividualMarket::Application.find(...)
  #   attestation = application.create_attestation(enrollment_terms: true, submission_terms: true)
  #
  class Attestation
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute application
    #   @return [IndividualMarket::Application] The application this attestation belongs to
    embedded_in :application, class_name: 'IndividualMarket::Application'

    # Examples of terms that a primary person/applicant must attest to. Change these as needed.
    field :enrollment_terms, type: Boolean
    # field :medicaid_terms, type: Boolean
    # field :medicaid_insurance_collection_terms, type: Boolean
    # field :report_change_terms, type: Boolean
    # field :parent_living_out_of_home_terms, type: Boolean
    # field :attestation_terms, type: Boolean
    # field :submission_terms, type: Boolean
  end
end
