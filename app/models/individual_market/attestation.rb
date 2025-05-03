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

    # @!attribute SIGNER_ROLE_KINDS
    # @return [Array<String>] Collection of all possible signer roles
    SIGNER_ROLE_KINDS = %w[admin assister broker consumer system].freeze

    # SignerID and SignerAt are only required for certain roles. The below is a list if roles that require a signer_id
    # @!attribute SIGNER_ROLE_KINDS_WITH_USER_SIGNER_INFO
    # @return [Array<String>] Collection of signer roles that require a signer_id and signed_at
    SIGNER_ROLE_KINDS_WITH_USER_SIGNER_INFO = %w[admin assister broker consumer].freeze

    # @!attribute signer_role
    #   @return [String] The role of the person who signed (consumer, admin, broker)
    field :signer_role, type: String

    # @!attribute signer_id
    #   @return [BSON::ObjectId] The ID of the user who signed
    field :signer_id, type: BSON::ObjectId

    # @!attribute signed_at
    #   @return [DateTime] The date and time when the attestation was signed
    field :signed_at, type: DateTime

    # Verifies that the signer_role is present and is one of the defined roles
    validates :signer_role, presence: true, inclusion: { in: SIGNER_ROLE_KINDS }

    # Validates that the signer_id and signed_at fields are present or absent based on the signer_role
    validate :verify_signer_id_and_signed_at

    # Returns the User who signed this attestation
    #
    # @return [User, nil] The user who signed the attestation, or nil if no signer_id is present
    def signed_user
      return @signed_user if defined?(@signed_user)

      @signed_user = signer_id ? User.find(signer_id) : nil
    end

    # @return [Boolean] Whether the attestation was signed by a consumer
    def signed_by_consumer?
      signer_role == :consumer
    end

    # @return [Boolean] Whether the attestation was signed by an admin
    def signed_by_admin?
      signer_role == :admin
    end

    # @return [Boolean] Whether the attestation was signed by a broker
    def signed_by_broker?
      signer_role == :broker
    end

    private

    # Validates the presence of signer_id and signed_at based on the signer_role
    #
    # @return [void]
    def verify_signer_id_and_signed_at
      if SIGNER_ROLE_KINDS_WITH_USER_SIGNER_INFO.include?(signer_role)
        errors.add(:signer_id, 'must be present') if signer_id.blank?
        errors.add(:signed_at, 'must be present') if signed_at.blank?
      else
        errors.add(:signer_id, 'must not be present') if signer_id.present?
        errors.add(:signed_at, 'must not be present') if signed_at.present?
      end
    end
  end
end
