# frozen_string_literal: true

module Eligibilities
  module Evidences
    # Controller for managing documents related to evidence in the eligibility process
    class DocumentsController < ::ApplicationController
      before_action :fetch_evidence
      before_action :check_for_uneditable_application
      after_action :build_determination, only: [:upload, :destroy]

      def upload
        authorize @evidence, :upload?

        operation = Operations::Eligibilities::Evidences::Documents::Upload.new
        result = operation.call({application: @application, evidence: @evidence, file: params[:file], current_user: current_user})
        redirect_location = determine_redirect_location

        if result.success?
          set_success_flash
          @success = true
        else
          flash[:error] = result.failure
        end

        redirect_to redirect_location
      end

      def download
        authorize @evidence, :download?

        document = get_document(params[:key])
        if document.present?
          bucket = env_bucket_name('id-verification')
          uri = "urn:openhbx:terms:v1:file_storage:s3:bucket:#{bucket}##{params[:key]}"
          send_data Aws::S3Storage.find(uri), download_options(document)
        else
          flash[:error] = "File does not exist or you are not authorized to access it."
          redirect_to main_app.verification_insured_families_path
        end
      end

      def destroy
        authorize @evidence, :destroy?

        operation = Operations::Eligibilities::Evidences::Documents::Delete.new
        result = operation.call({
                                  application: @application,
                                  evidence: @evidence,
                                  key: params[:doc_key],
                                  current_user: current_user
                                })

        if result.success?
          deletion_result = result.success
          flash[deletion_result[:type]] = deletion_result[:message]
          @success = true
        else
          flash[:danger] = result.failure
        end

        respond_to do |format|
          if EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)
            format.html { redirect_to main_app.verification_detail_insured_families_path(person_id: params['person_id'], eligibility_kind: params['eligibility_kind'], evidence_key: params['evidence_key']) }
          else
            format.html { redirect_to main_app.verification_insured_families_path }
          end
          format.js
        end
      end

      private

      def build_determination
        family = @application.family
        return unless @success && family.present? && EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)

        ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
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

      def set_success_flash
        if EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)
          flash[:success] = "Document successfully Submitted"
        else
          flash[:notice] = "File Saved"
        end
      end

      def permitted_params
        params.permit(:eligibility_id, :evidence_id, :application_gid,
                      :applicant_id,
                      :evidence_key,
                      :person_id,
                      :eligibility_kind,
                      :family,
                      file: [])
      end

      def fetch_evidence
        permitted = permitted_params

        @application = GlobalID::Locator.locate(permitted[:application_gid])
        return handle_not_found("Application not found") unless @application

        applicant = @application.applicants.where(id: permitted[:applicant_id]).first
        return handle_not_found("Applicant not found") unless applicant

        eligibility = applicant.eligibilities.where(id: permitted[:eligibility_id]).first
        return handle_not_found("Eligibility not found") unless eligibility

        @evidence = eligibility.evidences.where(id: permitted[:evidence_id]).first
        handle_not_found("Evidence not found") unless @evidence
      end

      def handle_not_found(error_message)
        flash[:error] = error_message
        redirect_to determine_redirect_location
      end

      def get_document(key)
        documents = @evidence.documents

        documents.detect do |doc|
          next if doc.identifier.blank?
          doc_key = doc.identifier.split('#').last
          doc_key == key
        end
      end

      def env_bucket_name(bucket_name)
        aws_env = ENV['AWS_ENV'] || "qa"
        subdomain = EnrollRegistry[:enroll_app].setting(:subdomain).item
        "#{subdomain}-enroll-#{bucket_name}-#{aws_env}"
      end

      def download_options(document)
        options = {}
        options[:content_type] = document.format
        options[:filename] = document.title
        options
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
    end
  end
end
