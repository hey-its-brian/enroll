# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Individual
    # Create new enrollments based on new eligibility determination
    class OnNewDetermination
      include Dry::Monads[:do, :result]
      include FloatHelper

      def call(params)
        values = yield validate(params)
        eligible_enrollments    = yield fetch_enrollments_to_renew(values)
        generate_enrollments    = yield generate_enrollments(eligible_enrollments)
        Success(generate_enrollments)
      end

      private

      def validate(params)
        return Failure("Missing Family") unless params[:family].is_a?(Family)
        return Failure("Missing Year") if params[:year].blank?
        @generation_reason = params[:generation_reason] || :application_determination
        @determination_type = params[:determination_type]

        Success(params)
      end

      # Find the enrollments to update for the determination
      # Only include enrolled or renewing individual market health enrollments for the application year that meet the determination_type criteria
      # @param values [Hash] the input parameters containing family and year
      # @return [Dry::Monads::Result] Success with array of enrollments or Failure with error message
      def fetch_enrollments_to_renew(values)
        enrollments = values[:family].active_household.hbx_enrollments.enrolled_and_renewal.individual_market.by_health.by_year(values[:year])
        enrollments_for_determination = enrollments.reject { |enrollment| should_reject_enrollment?(enrollment) }
        return Success([]) if enrollments_for_determination.blank?

        enrollments_with_products = enrollments_for_determination.reject { |enrollment| enrollment.product.blank? }
        return Failure("No enrollments with products") if enrollments_with_products.empty?

        Success(enrollments_with_products.sort_by(&:created_at))
      end

      def generate_enrollments(enrollments)
        return Success(:no_eligible_enrollments) if enrollments.empty?

        exclude_enrollments_list = enrollments.map(&:hbx_id)
        enrollments.each do |enrollment|
          elected_aptc_pct = if EnrollRegistry.feature_enabled?(:temporary_configuration_enable_multi_tax_household_feature)
                               default_percentage = EnrollRegistry[:aca_individual_assistance_benefits].setting(:default_applied_aptc_percentage).item
                               enrollment.elected_aptc_pct.to_f > 0.0 ? enrollment.elected_aptc_pct.to_f : default_percentage
                             end

          attrs = {
            enrollment_id: enrollment.id,
            elected_aptc_pct: elected_aptc_pct,
            exclude_enrollments_list: exclude_enrollments_list,
            generation_reason: @generation_reason
          }

          ::Insured::Forms::SelfTermOrCancelForm.for_aptc_update_post(attrs)
        end
        Success(:applied_aptc_to_enrollments)
      end

      # Determine if an enrollment should be rejected based on determination type
      # @param enrollment [HbxEnrollment] the enrollment to check
      # @return [Boolean] true if the enrollment should be rejected, false otherwise
      def should_reject_enrollment?(enrollment)
        case @determination_type
        when :financial_assistance # only non-catastrophic plans are considered for financial assistance determination enrollment updates
          enrollment.product.metal_level_kind == :catastrophic
        else
          false
        end
      end
    end
  end
end
