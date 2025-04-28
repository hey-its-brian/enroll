# frozen_string_literal: true

module Validators
  module Families
    class ApplicationContract < Dry::Validation::Contract
      include ::ResourceRegistryHelper

      params do
        required(:family_id).filled(Types::Bson)
        required(:assistance_year).filled(:integer)
        optional(:years_to_renew).maybe(:integer)
        optional(:renewal_consent_through_year).maybe(:integer)
        required(:benchmark_product_id).filled(Types::Bson)
        optional(:is_ridp_verified).maybe(:bool)
        required(:applicants).array(:hash)
        optional(:origin).maybe(:symbol)
        optional(:generation_reason).maybe(:symbol)
      end

      rule(:origin) do
        if qhp_application_feature_enabled?
          key.failure('origin is required') unless key?
          key.failure('origin is invalid') if key? && ::FinancialAssistance::Application::ORIGIN_KINDS.exclude?(value)
        end
      end

      rule(:generation_reason) do
        if qhp_application_feature_enabled?
          key.failure('generation_reason is required') unless key?
          key.failure('generation_reason is invalid') if key? && ::FinancialAssistance::Application::GENERATION_REASONS.exclude?(value)
        end
      end

      rule(:family_id) do
        if key? && value
          result = Operations::Families::Find.new.call(id: value)
          key.failure(text: 'invalid family_id', error: result.errors.to_h) if result&.failure?
        end
      end

      rule(:applicants).each do
        if key? && value
          if value.is_a?(Hash)
            result = ::FinancialAssistance::Validators::ApplicantContract.new.call(value)
            key.failure(text: "invalid applicant", error: result.errors.to_h) if result&.failure?
          else
            key.failure(text: "invalid applicant. Expected a hash.")
          end
        end
      end
    end
  end
end
