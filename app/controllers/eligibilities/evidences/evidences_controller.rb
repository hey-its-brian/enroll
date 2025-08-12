# frozen_string_literal: true

module Eligibilities
  module Evidences
    # Controller for managing V3 evidence verification actions in the eligibility process
    class EvidencesController < ::ApplicationController
      before_action :fetch_evidence
      before_action :check_for_uneditable_application
      after_action :build_determination

      # Updates evidence verification status through admin actions (verify/reject)
      # @return [void] Redirects with flash messages based on operation result
      def update
        authorize HbxProfile, :can_update_verification_type?

        update_reason = params[:verification_reason]
        admin_action = params[:admin_action]
        reasons_list = fetch_reasons_list
        if reasons_list.include?(update_reason)
          result = Operations::Eligibilities::Evidences::Update.new.call(
            evidence: @evidence,
            application: @application,
            admin_action: admin_action,
            update_reason: update_reason,
            current_user: current_user
          )

          if result.success?
            flash[:success] = result.success
            @success = true
          else
            flash[:error] = result.failure
          end
        else
          flash[:error] = "Please provide a verification reason."
        end

        redirect_to determine_redirect_location
      end

      # Extends the due date for an V3 evidence record
      # @param due_on [Date] The new due date for the evidence
      # @param extension_period [Integer] The number of days to extend the due date by
      # @return [void] Redirects with flash messages based on operation result
      def extend_due_date
        authorize HbxProfile, :can_extend_due_date?

        result = Operations::Eligibilities::Evidences::ExtendDueDate.new.call(
          evidence: @evidence,
          application: @application,
          current_user: current_user,
          due_on: params[:due_on],
          extension_period: params[:extension_period]
        )

        if result.success?
          flash[:success] = result.success
          @success = true
        else
          flash[:danger] = result.failure
        end

        redirect_back(fallback_location: determine_redirect_location)
      end

      # Requests a hub call for the V3 evidence verification
      # @return [void] Responds with success or error message based on operation result
      def fed_hub_request
        authorize HbxProfile, :can_call_hub?

        if @eligibility.key.to_s == 'individual_market_eligibility'
          ivl_hub_call_keys = ::Eligibilities::V3::IndividualMarketEligibility::HUB_CALL_EVIDENCES
          raise "Call hub feature is not available for #{@evidence.type_name}" unless ivl_hub_call_keys.include?(@evidence.key)
        end

        permitted_params = {
          action_name: params[:admin_action],
          update_reason: "Requested Hub for verification",
          updated_by: current_user.oim_id
        }
        result = @evidence.call_hub(permitted_params)

        if result.success?
          key = :success
          message = "request submitted successfully"
          @success = true
        else
          key = :error
          message = "unable to submit request"
        end

        respond_to do |format|
          format.html do
            flash[key] = message
            redirect_back(fallback_location: determine_redirect_location)
          end
          format.js
        end
      end

      private

      def fetch_reasons_list
        case @eligibility.key.to_s
        when 'aptc_csr_eligibility'
          FinancialAssistance::Evidence::VERIFY_REASONS + FinancialAssistance::Evidence::REJECT_REASONS
        when 'individual_market_eligibility'
          VlpDocument::VERIFICATION_REASONS + VlpDocument::ALL_TYPES_REJECT_REASONS + VlpDocument::CITIZEN_IMMIGR_TYPE_ADD_REASONS
        end
      end

      def fetch_evidence
        @application = GlobalID::Locator.locate(params[:application_gid])
        return handle_not_found("Application not found") unless @application

        applicant = @application.applicants.where(id: params[:applicant_id]).first
        return handle_not_found("Applicant not found") unless applicant

        @eligibility = applicant.eligibilities.where(id: params[:eligibility_id]).first
        return handle_not_found("Eligibility not found") unless @eligibility

        @evidence = @eligibility.evidences.where(id: params[:id]).first
        handle_not_found("Evidence not found") unless @evidence
      end

      def handle_not_found(error_message)
        flash[:error] = error_message
        redirect_to determine_redirect_location
      end

      def determine_redirect_location
        if EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)
          verification_detail_insured_families_path(
            person_id: params['person_id'],
            eligibility_kind: params['eligibility_kind'],
            evidence_key: params['evidence_key']
          )
        else
          verification_insured_families_path
        end
      end

      # Checks if the application is in an uneditable state and, if so, sets a flash message and redirects to the applications path.
      #
      # @return [void]
      def check_for_uneditable_application
        status = @application.is_a?(::FinancialAssistance::Application) ? @application.aasm_state : @application.current_state
        return if ::FinancialAssistance::Application::UNEDITABLE_STATES.exclude?(status)

        flash[:alert] = l10n('faa.flash_alerts.uneditable_application')
        redirect_to(current_applications_insured_sbm_applications_path) and return
      end

      def build_determination
        family = @application.family
        return unless @success && family.present? && EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)

        ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
      end
    end
  end
end
