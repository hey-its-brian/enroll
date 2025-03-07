# frozen_string_literal: true

class Insured::VerificationDocumentsController < ApplicationController
  include ApplicationHelper
  include VerificationHelper

  before_action :set_current_person
  before_action :find_type, :find_docs_owner, :alive_status_authorization?, only: [:upload]
  before_action :check_for_consumer_role
  after_action :build_determination, only: [:upload]

  def upload
    authorize @consumer_role, :verification_document_upload?

    @doc_errors = []
    redirect_location = if EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)
                          verification_detail_insured_families_path(person_id: params['person_id'], eligibility_kind: params['eligibility_kind'], evidence_key: params['evidence_key'])
                        else
                          verification_insured_families_path
                        end
    if params[:file].blank?
      flash[:error] = "File not uploaded. Please select the file to upload."
    elsif !valid_file_uploads?(params[:file], FileUploadValidator::VERIFICATION_DOC_TYPES)
      redirect_to redirect_location
      return
    else
      params[:file].each do |file|
        doc_uri = Aws::S3Storage.save(file_path(file), 'id-verification')
        if doc_uri.present? && update_vlp_documents(file_name(file), doc_uri)
          add_type_history_element(file)
          flash_type, flash_message = EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary) ? [:success, "Document successfully Submitted"] : [:notice, "File Saved"]
          flash[flash_type] = flash_message
          @success = true
        else
          flash[:error] = "Could not save file#{". #{@doc_errors.join('. ')}" if @doc_errors.present?}"
          redirect_back(fallback_location: redirect_location) and return nil
        end
      end
    end
    redirect_to redirect_location
  end

  def download
    authorize @consumer_role, :verification_document_download?
    document = get_document(params[:key])
    if document.present?
      bucket = env_bucket_name('id-verification')
      uri = "urn:openhbx:terms:v1:file_storage:s3:bucket:#{bucket}##{params[:key]}"
      send_data Aws::S3Storage.find(uri), download_options(document)
    else
      flash[:error] = "File does not exist or you are not authorized to access it."
      redirect_to verification_insured_families_path
    end
    vlp_docs_clean(@person)
  end

  private

  def find_type
    find_docs_owner
    @verification_type = @docs_owner.verification_types.find(params[:verification_type]) if params[:verification_type]
  end

  def check_for_consumer_role
    @consumer_role = @person.consumer_role
    return if @consumer_role

    flash[:error] = "No consumer role exists, you are not authorized to upload documents"
    redirect_to verification_insured_families_path
  end

  def alive_status_authorization?
    return true if can_display_v_type?(@verification_type)

    flash[:error] = "You are not authorized to upload this document"
    redirect_to verification_insured_families_path
  end

  def file_path(file)
    file.tempfile.path
  end

  def file_name(file)
    file.original_filename
  end

  def find_docs_owner
    @docs_owner = Person.find(params[:docs_owner]) if params[:docs_owner]
  end

  def update_vlp_documents(title, file_uri)
    document = @verification_type.vlp_documents.build
    success = document.update_attributes({:identifier=>file_uri, :subject => title, :title=>title, :status=>"downloaded"})
    @verification_type.update_attributes(:rejected => false, :validation_status => "review", :update_reason => "document uploaded")
    @doc_errors = document.errors.full_messages unless success
    @docs_owner.save
  end

  def update_paper_application(title, file_uri)
    document = @docs_owner.resident_role.vlp_documents.build
    success = document.update_attributes({:identifier=>file_uri, :subject => title, :title=>title, :status=>"downloaded", :verification_type=>params[:verification_type]})
    @doc_errors = document.errors.full_messages unless success
    @docs_owner.save
  end

  def get_document(key)
    document = @person.consumer_role.find_vlp_document_by_key(key)
    return document if document && can_display_v_type?(document.documentable)
  end

  def download_options(document)
    options = {}
    options[:content_type] = document.format
    options[:filename] = document.title
    options
  end

  def add_type_history_element(file)
    actor = current_user ? current_user.email : "external source or script"
    action = "Upload #{file_name(file)}" if params[:action] == "upload"
    params = {action: action, modifier: actor}
    statuses = validation_statuses
    params.merge!({from_validation_status: statuses[:from_validation_status], to_validation_status: statuses[:to_validation_status] }) if @verification_type.type_name == 'Alive Status'
    @verification_type.add_type_history_element(params)
  end

  def validation_statuses
    status = {from_validation_status: nil, to_validation_status: nil}
    history_track = @verification_type.history_tracks.last
    if history_track.modified["validation_status"].present? && history_track.original["validation_status"].present?
      status[:from_validation_status] = history_track.tracked_changes["validation_status"]["from"]
      status[:to_validation_status] = history_track.tracked_changes["validation_status"]["to"]
    end

    status
  end

  def vlp_docs_clean(person)
    existing_documents = person.consumer_role.vlp_documents
    person_consumer_role=Person.find(person.id).consumer_role
    person_consumer_role.vlp_documents =[]
    person_consumer_role.save
    person_consumer_role=Person.find(person.id).consumer_role
    person_consumer_role.vlp_documents = existing_documents.uniq
    person_consumer_role.save
  end

  def build_determination
    family = Family.where(id: params[:family]).first
    return unless @success && family.present? && EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)

    ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family, effective_date: TimeKeeper.date_of_record)
  end
end
