# frozen_string_literal: true

module Operations
  module Eligibilities
    module Evidences
      module Documents
        # This class handles the deletion of documents associated with evidence verification.
        class Delete
          include Dry::Monads[:do, :result]
          include L10nHelper

          # Handles the deletion of documents for evidence verification
          #
          # @param params [Hash] delete parameters including evidence and document key
          # @return [Dry::Monads::Result] Success with deletion results or Failure with error message
          def call(params)
            validated_params = yield validate(params)
            document = yield find_document(validated_params[:evidence], validated_params[:key])
            deletion_result = yield process_document_deletion(document, validated_params[:evidence], validated_params[:current_user])
            _result = yield persist_changes(validated_params[:application])

            Success(deletion_result)
          end

          private

          # Validates the input parameters
          #
          # @param params [Hash] parameters containing evidence and document key
          # @return [Dry::Monads::Result] Success with params or Failure with error message
          def validate(params)
            return Failure("Unable to fetch evidence") if params[:evidence].blank?
            return Failure("Document key is required") if params[:key].blank?
            return Failure("Current user is required") if params[:current_user].blank?

            Success(params)
          end

          # Finds the document by key
          #
          # @param evidence [Evidence] the evidence record
          # @param key [String] the document key
          # @return [Dry::Monads::Result] Success with document or Failure with error message
          def find_document(evidence, key)
            documents = evidence.documents
            document = documents.detect do |doc|
              next if doc.identifier.blank?
              doc_key = doc.identifier.split('#').last
              doc_key == key
            end

            return Failure(l10n("documents.controller.missing_document_message", contact_center_phone_number: EnrollRegistry[:enroll_app].settings(:contact_center_short_number).item)) unless document

            Success(document)
          end

          # Processes the document deletion
          #
          # @param document [Document] the document to delete
          # @param evidence [Evidence] the evidence record
          # @param current_user [User] the user performing the deletion
          # @return [Dry::Monads::Result] Success with results or Failure with error message
          def process_document_deletion(document, evidence, current_user)
            return Failure("Document cannot be deleted because type is verified") unless evidence.type_unverified?

            document.delete
            return Failure("Failed to delete document") unless document.destroyed?

            _history = yield add_verification_history(document, evidence, current_user)
            deletion_result = yield handle_post_deletion(document, evidence, current_user)

            Success(deletion_result)
          end

          # Handles actions after successful deletion
          #
          # @param document [Document] the deleted document
          # @param evidence [Evidence] the evidence record
          # @param current_user [User] the user performing the deletion
          # @return [Dry::Monads::Result] Success with result message or Failure with error message
          def handle_post_deletion(document, evidence, current_user)
            remaining_documents = evidence.documents - [document]

            if remaining_documents.empty?
              _result = yield handle_all_documents_deleted(evidence, current_user)
              Success({ message: "All documents were deleted. Action needed", type: :danger })
            else
              Success({ message: "Document deleted.", type: :success })
            end
          end

          # Handles the case when all documents are deleted
          #
          # @param evidence [Evidence] the evidence record
          # @param current_user [User] the user performing the deletion
          # @return [Dry::Monads::Result] Success or Failure
          def handle_all_documents_deleted(evidence, current_user)
            evidence.mark_as_rejected
            evidence.updated_by = current_user.oim_id

            Success(evidence)
          rescue StandardError => e
            Rails.logger.error("Document Delete - Error handling all documents deleted: #{e.message}")
            Failure("Failed to update evidence after deleting all documents: #{e.message}")
          end

          # Adds verification history entry for deletion
          #
          # @param document [Document] the deleted document
          # @param evidence [Evidence] the evidence record
          # @param current_user [User] the user performing the deletion
          # @return [Dry::Monads::Result] Success with history or Failure with error message
          def add_verification_history(document, evidence, current_user)
            actor = current_user ? current_user.oim_id : "external source or script"
            action = "Delete #{document.title}"
            update_reason = "document deleted"

            evidence.build_verification_history(action, update_reason, actor)
            Success(evidence)
          rescue StandardError => e
            Rails.logger.error("Document Delete - Error adding verification history: #{e.message}")
            Failure("Verification history failed: #{e.message}")
          end

          # Persists all changes on application at once
          #
          # @return [Dry::Monads::Result] Success with application or Failure with error message
          def persist_changes(application)
            Success(application) if application.save!
          rescue StandardError => e
            Rails.logger.error("Application save failed: #{e.message}")
            Failure("Application save failed: #{e.message}")
          end
        end
      end
    end
  end
end
