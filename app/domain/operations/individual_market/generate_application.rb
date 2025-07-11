# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    # This class constructs ivl_application params_hash,
    # then validates it against the ApplicationContract
    # then calls Operations::IndividualMarket::Create
    # gets back IndividualMarket::Application object_id
    class GenerateApplication
      include Dry::Monads[:do, :result]
      include ResourceRegistryHelper

      # @param [ FamilyId ] family_id bson_id of a family
      # @param [ Origin ] origin
      # @param [ GenerationReason ] generation_reason
      # @return [ IndividualMarket::Application ] application_id
      def call(params)
        validated_params             = yield validate(params)
        application_params           = yield parse_family(validated_params)
        application_id               = yield apply(application_params)
        new_application              = yield fetch_application(application_id)
        _cancelled                   = yield cancel_previous_applications(new_application)

        Success(application_id)
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

      def apply(application_params)
        result = ::Operations::IndividualMarket::Application::Create.new.call(params: application_params)

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
