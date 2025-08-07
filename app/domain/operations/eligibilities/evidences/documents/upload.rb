# frozen_string_literal: true

module Operations
  module Eligibilities
    module Evidences
      module Documents
        # Upload class handles the upload of documents for evidence verification documents
        class Upload
          include Dry::Monads[:do, :result]
          include FileUploadHelper

          # Handles the upload of documents for evidence verification
          #
          # @param params [Hash] upload parameters including files and evidence info
          # @param current_user [User] the user performing the upload
          # @return [Dry::Monads::Result] Success with upload results or Failure with error message
          def call(params)
            validated_params = yield validate(params)
            files = yield validate_files(validated_params[:file])
            upload_results = yield process_file_uploads(files, params[:current_user])

            Success(upload_results)
          end

          private

          def validate(params)
            return Failure("Unable to fetch application") if params[:application].blank?
            return Failure("Unable to fetch evidence") if params[:evidence].blank?

            @application = params[:application]
            @evidence = params[:evidence]
            Success(params)
          end

          # Validates the uploaded files
          #
          # @param files [Array] array of uploaded files
          # @return [Dry::Monads::Result] Success with files or Failure with error message
          def validate_files(files)
            return Failure("File not uploaded. Please select the file to upload.") if files.blank?

            return Failure("Invalid file type uploaded") unless valid_file_uploads?(files, FileUploadValidator::VERIFICATION_DOC_TYPES)

            Success(files)
          end

          # Processes all file uploads
          #
          # @param files [Array] array of files to upload
          # @param current_user [User] the user performing the upload
          # @return [Dry::Monads::Result] Success with results or Failure with error message
          def process_file_uploads(files, current_user)
            results = []
            errors = []

            files.each do |file|
              result = process_single_file(file, current_user)
              if result.success?
                results << result.success
              else
                errors << result.failure
              end
            end

            return Failure("Upload errors: #{errors.join(', ')}") if errors.any?

            # Persist application with all changes at once
            _persist_result = yield persist_changes

            Success(results)
          end

          # Processes a single file upload
          #
          # @param file [File] the file to upload
          # @param current_user [User] the user performing the upload
          # @return [Dry::Monads::Result] Success with document or Failure with error message
          def process_single_file(file, current_user)
            doc_uri = yield upload_to_storage(file)
            document = yield build_document(@evidence, file, doc_uri)
            _history = yield add_verification_history(@evidence, file, current_user)
            _evidence = yield update_evidence_status(@evidence, current_user)

            Success(document)
          end

          # Uploads file to S3 storage
          #
          # @param file [File] the file to upload
          # @return [Dry::Monads::Result] Success with URI or Failure with error message
          def upload_to_storage(file)
            doc_uri = Aws::S3Storage.save(file.tempfile.path, 'id-verification')

            if doc_uri.present?
              Success(doc_uri)
            else
              Failure("Failed to upload file to storage")
            end
          rescue StandardError => e
            Rails.logger.error("Document Upload - Error uploading to S3: #{e.message}")
            Failure("Storage upload failed: #{e.message}")
          end

          # Creates a document record
          #
          # @param evidence [Evidence] the evidence record
          # @param file [File] the uploaded file
          # @param doc_uri [String] the storage URI
          # @return [Dry::Monads::Result] Success with document or Failure with error message
          def build_document(evidence, file, doc_uri)
            document = evidence.documents.build(
              identifier: doc_uri,
              subject: file.original_filename,
              title: file.original_filename,
              status: "downloaded"
            )

            if document.valid?
              Success(document)
            else
              Rails.logger.error("Document Upload - Document validation failed: #{document.errors.full_messages}")
              Failure("Document creation failed: #{document.errors.full_messages.join(', ')}")
            end
          rescue StandardError => e
            Rails.logger.error("Document Upload - Error creating document: #{e.message}")
            Failure("Document creation failed: #{e.message}")
          end

          # Adds verification history entry
          #
          # @param evidence [Evidence] the evidence record
          # @param file [File] the uploaded file
          # @param current_user [User] the user performing the upload
          # @return [Dry::Monads::Result] Success with history or Failure with error message
          def add_verification_history(evidence, file, current_user)
            actor = current_user ? current_user.oim_id : "external source or script"
            action = "Upload #{file.original_filename}"
            update_reason = "document uploaded"

            evidence.add_to_history(action, update_reason, actor)
            Success(evidence)
          rescue StandardError => e
            Rails.logger.error("Document Upload - Error adding verification history: #{e.message}")
            Failure("Verification history failed: #{e.message}")
          end

          # Updates evidence status and metadata
          #
          # @param evidence [Evidence] the evidence record
          # @param current_user [User] the user performing the upload
          # @return [Dry::Monads::Result] Success with evidence or Failure with error message
          def update_evidence_status(evidence, current_user)
            evidence.move_to_review! if evidence.can_move_to_review?
            evidence.updated_by = current_user.oim_id

            Success(evidence)
          rescue StandardError => e
            Rails.logger.error("Document Upload - Error updating evidence: #{e.message}")
            Failure("Evidence update failed: #{e.message}")
          end

          # Persists all changes on application at once
          #
          # @return [Dry::Monads::Result] Success with application or Failure with error message
          def persist_changes
            Success(@application) if @application.save!
          rescue StandardError => e
            Rails.logger.error("Application save failed: #{e.message}")
            Failure("Application save failed: #{e.message}")
          end
        end
      end
    end
  end
end
