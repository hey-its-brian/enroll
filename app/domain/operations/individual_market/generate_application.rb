# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    # This class constructs ivl_application params_hash,
    # then validates it against the ApplicationContract
    # then calls Operations::IndividualMarket::Build to build the application
    # and its associated applicants. Finally, it cancels any previous applications for the same family.
    class GenerateApplication
      include Dry::Monads[:do, :result]
      include ResourceRegistryHelper

      # @param [ FamilyId ] family_id bson_id of a family
      # @param [ Origin ] origin
      # @param [ GenerationReason ] generation_reason
      # @return [ IndividualMarket::Application ] application
      def call(params)
        validated_params             = yield validate(params)
        family                       = yield fetch_family(validated_params)
        application_params           = yield parse_family(family)
        application                  = yield build(application_params)
        _cancelled                   = yield cancel_previous_applications(application)

        Success(application)
      end

      private

      # Validates the input parameters
      #
      # @param [Hash] params
      # @option params [BSON::ObjectId] :family_id
      # @option params [Family] :family
      # @option params [Integer] :assistance_year
      # @option params [Symbol] :origin
      # @option params [Symbol] :generation_reason
      # @option params [Boolean] :renewal
      #
      # @return [Dry::Monads::Result] Success with params or Failure with error message
      def validate(params)
        return Failure('family_id or family is required') if !params[:family_id].is_a?(BSON::ObjectId) && params[:family].blank?
        return Failure(I18n.t('faa.errors.invalid_origin_source_error')) if invalid_origin_source?(params)
        return Failure(I18n.t('faa.errors.invalid_generation_reason_error')) if invalid_generation_reason?(params)
        return Failure(I18n.t('faa.errors.invalid_assistance_year_error')) if invalid_assistance_year?(params)

        @renewal = params[:renewal] || false

        Success(params)
      end

      # Checks if the origin is valid
      # @param [Hash] params
      # @option params [Symbol] :origin
      def invalid_origin_source?(params)
        @origin = params[:origin]
        ::IndividualMarket::Application::ORIGIN_KINDS.exclude?(@origin)
      end

      # Checks if the generation reason is valid
      # @param [Hash] params
      # @option params [Symbol] :generation_reason
      def invalid_generation_reason?(params)
        @generation_reason = params[:generation_reason]
        ::IndividualMarket::Application::GENERATION_REASONS.exclude?(params[:generation_reason])
      end

      def invalid_assistance_year?(params)
        return false unless params[:assistance_year].present?

        @assistance_year = params[:assistance_year].to_i
        !params[:assistance_year].to_s.match?(/\A\d+\z/)
      end

      # Fetches the family based on the provided family_id or family object
      #
      # @param [Hash] validated_params
      # @option validated_params [BSON::ObjectId] :family_id
      # @option validated_params [Family] :family
      #
      # @return [Dry::Monads::Result] Success with family or Failure with error message
      def fetch_family(validated_params)
        if validated_params[:family].is_a?(Family)
          Success(validated_params[:family])
        else
          ::Operations::Families::Find.new.call(id: validated_params[:family_id])
        end
      end

      # Parses the family and prepares application attributes
      #
      # @param [Family] family
      #
      # @return [Dry::Monads::Result] Success with application attributes or Failure with validation errors
      def parse_family(family)
        contract_result = ::Validators::IndividualMarket::ApplicationContract.new.call(
          application_attributes(family)
        )
        contract_result.success? ? Success(contract_result.to_h) : Failure(contract_result.errors)
      end

      # Builds the application using the provided application parameters
      #
      # @param [Hash] application_params
      #
      # @return [Dry::Monads::Result] Success with application or Failure with error message
      def build(application_params)
        result = ::Operations::IndividualMarket::Application::Build.new.call(params: application_params)

        if result.success?
          Success(result.success)
        else
          Failure(result.failure)
        end
      end

      # Constructs the application attributes based on the family and assistance year
      #
      # @param [Family] family
      #
      # @return [Hash] application attributes
      def application_attributes(family)
        application_attrs = {
          assistance_year: fetch_assistance_year(family),
          family_id: family.id,
          generation_reason: @generation_reason,
          is_renewal: @renewal,
          origin: @origin
        }

        application_attrs.merge!({applicants: applicants_attributes(family)})
        application_attrs
      end

      # Fetches the assistance year, either from the provided params or from the family
      #
      # @param [Family] family
      #
      # @return [Integer] assistance year
      def fetch_assistance_year(family)
        if @assistance_year.present?
          @assistance_year
        else
          family.application_applicable_year
        end
      end

      def applicants_attributes(family)
        family.active_family_members.inject([]) do |members_array, family_member|
          member_attrs_result = ::Operations::IndividualMarket::ParseApplicant.new.call({family_member: family_member})
          members_array << member_attrs_result.success if member_attrs_result.success?
          members_array
        end
      end

      # Cancels previous applications if the renewal flag is false
      #
      # @param [IndividualMarket::Application] application
      #
      # @return [Dry::Monads::Result] Success message or Failure with error message
      #
      # @note Initial applications should not be cancelled for system generated applications (renewals or expired_rop).
      def cancel_previous_applications(application)
        if application.is_renewal
          Success('Applications should not be cancelled for renewal applications.')
        else
          ::Operations::Sbm::Applications::CancelPreviousApplications.new.call(application: application)
        end
      end
    end
  end
end
