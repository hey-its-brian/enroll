# frozen_string_literal: true

module Eligibilities
  module Evidences
    # Controller for managing documents related to V3 evidence in the eligibility process
    class DocumentsController < ::ApplicationController
      layout 'progress'
      include ResourceRegistryHelper

      before_action :set_current_person, only: [:index]
      before_action :fetch_evidence
      before_action :set_evidence_context, only: [:index]
      before_action :check_for_uneditable_application, only: [:upload, :destroy]
      after_action :build_determination, only: [:upload, :destroy]

      # Handles the index action for documents related to evidence
      # This action authorizes the evidence and retrieves all documents related to it.
      # If successful, it assigns the documents to instance variables and renders the index view.
      # If it fails, it redirects with an error message.
      # @return [void]
      # @note This action is only used for the V3 evidence verification process.
      def index
        authorize @evidence, :index?

        operation = Operations::Eligibilities::Evidences::Documents::Index.new
        result = operation.call(params: params, evidence: @evidence)

        if result.success?
          # Assign all returned values to instance variables
          result.value!.each do |key, value|
            instance_variable_set("@#{key}", value)
          end

          if request.headers["Accept"] == "text/html" && request.xhr?
            render partial: "table", locals: {
              uploads: @uploads,
              selected_year: @selected_year,
              per_page: @per_page,
              page: @page,
              total_pages: @total_pages,
              document_app_map: @document_app_map
            }
          end
        else
          flash[:error] = result.failure
          redirect_to determine_redirect_location
        end
      end

      # Handles the upload of documents related to evidence
      # This action authorizes the evidence and processes the file upload.
      # If successful, it redirects to the appropriate page with a success message.
      # If it fails, it redirects with an error message.
      # @param file [ActionDispatch::Http::UploadedFile] The file to be uploaded
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

      # Handles the download of documents related to evidence
      # This action authorizes the evidence and retrieves the document by its key.
      # If the document exists, it sends the file to the user for download.
      # If the document does not exist or the user is not authorized, it redirects with an error message.
      # @param key [String] The key of the document to be downloaded
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

      # Handles the deletion of documents related to evidence
      # This action authorizes the evidence and attempts to delete the document by its key.
      # If successful, it sets a success message and redirects to the appropriate page.
      # If it fails, it sets an error message and redirects.
      # @param doc_key [String] The key of the document to be deleted
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

      # Sets the context for the V3 evidence
      # This method retrieves the member and evidence delegator for the V3 evidence.
      # If successful, it assigns the values to instance variables.
      # If it fails, it redirects with an error message.
      # @return [void]
      # @note This method is only used for the V3 evidence verification process.
      def set_evidence_context
        result = Operations::Families::Verifications::Summary::EvidenceQuery.new.call(
          family: @application.family,
          person_id: params[:person_id],
          evidence_key: params[:evidence_key],
          eligibility_kind: params[:eligibility_kind],
          inactive: params[:inactive]
        )

        if result.success?
          value = result.value!

          @member = value[:member]
          @evidence_delegator = value[:evidence]
        else
          redirect_back(fallback_location: verification_insured_families_path, :flash => {error: result.failure})
        end
      end

      def build_determination
        family = @application.family
        return unless @success && family.present? && EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)

        ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
      end

      def determine_redirect_location
        if EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)
          if qhp_application_feature_enabled?
            eligibility_evidence_path(
              eligibility_id: @eligibility.id,
              id: @evidence.id,
              application_gid: params[:application_gid],
              applicant_id: @applicant.id,
              person_id: params[:person_id],
              eligibility_kind: params[:eligibility_kind],
              evidence_key: params[:evidence_key],
              family_id: @family.id
            )
          else
            verification_detail_insured_families_path(
              person_id: params['person_id'],
              eligibility_kind: params['eligibility_kind'],
              evidence_key: params['evidence_key']
            )
          end
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

        @family = @application.family
        @applicant = @application.applicants.where(id: permitted[:applicant_id]).first
        return handle_not_found("Applicant not found") unless @applicant

        @eligibility = @applicant.eligibilities.where(id: permitted[:eligibility_id]).first
        return handle_not_found("Eligibility not found") unless @eligibility

        @evidence = @eligibility.evidences.where(id: permitted[:evidence_id]).first
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
