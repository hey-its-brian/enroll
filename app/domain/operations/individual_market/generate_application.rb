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
        application_params           = yield parse_family(validated_params)
        application                  = yield build(application_params)
        _cancelled                   = yield cancel_previous_applications(application)

        Success(application)
      end

      private

      def validate(params)
        return Failure('family_id is expected in BSON format') unless params[:family_id].is_a?(BSON::ObjectId)
        return Failure(I18n.t('faa.errors.invalid_origin_source_error')) if invalid_origin_source?(params)
        return Failure(I18n.t('faa.errors.invalid_generation_reason_error')) if invalid_generation_reason?(params)

        Success(params)
      end

      def invalid_origin_source?(params)
        @origin = params[:origin]
        ::IndividualMarket::Application::ORIGIN_KINDS.exclude?(@origin)
      end

      def invalid_generation_reason?(params)
        @generation_reason = params[:generation_reason]
        ::IndividualMarket::Application::GENERATION_REASONS.exclude?(params[:generation_reason])
      end

      def parse_family(params)
        family_find_result = ::Operations::Families::Find.new.call(id: params[:family_id])
        return family_find_result if family_find_result.failure?

        family = family_find_result.success
        contract_result = ::Validators::IndividualMarket::ApplicationContract.new.call(application_attributes(family))
        contract_result.success? ? Success(contract_result.to_h) : Failure(contract_result.errors)
      end

      def build(application_params)
        result = ::Operations::IndividualMarket::Application::Build.new.call(params: application_params)

        if result.success?
          Success(result.success)
        else
          Failure(result.failure)
        end
      end

      def application_attributes(family)
        application_attrs = {
          family_id: family.id,
          assistance_year: family.application_applicable_year,
          origin: @origin,
          generation_reason: @generation_reason
        }

        application_attrs.merge!({applicants: applicants_attributes(family)})
        application_attrs
      end

      def applicants_attributes(family)
        family.active_family_members.inject([]) do |members_array, family_member|
          member_attrs_result = ::Operations::IndividualMarket::ParseApplicant.new.call({family_member: family_member})
          members_array << member_attrs_result.success if member_attrs_result.success?
          members_array
        end
      end

      def fetch_application(application_id)
        application = ::IndividualMarket::Application.where(id: application_id).first
        application ? Success(application) : Failure("Application with id #{application_id} not found.")
      end

      def cancel_previous_applications(application)
        ::Operations::Sbm::Applications::CancelPreviousApplications.new.call(application: application)
      end
    end
  end
end
