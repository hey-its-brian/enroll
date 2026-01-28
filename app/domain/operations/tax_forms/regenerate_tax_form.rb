# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module TaxForms
    # This class copies a tax form document from notice bucket to paper notices bucket
    # and also generates an inbox message
    class RegenerateTaxForm
      include ::L10nHelper
      include Dry::Monads[:do, :result]

      def call(opts)
        validate_params = yield validate_params(opts[:params])
        resource = yield fetch_resource(validate_params)
        document = yield fetch_document(resource, validate_params[:relation_id])
        _copy_to_s3 = yield copy_to_s3(resource, document, validate_params, opts[:user])
        inbox_message = yield generate_inbox_message(resource, document)

        Success(inbox_message)
      end

      private

      def validate_params(params)
        result = ::Validators::Documents::DownloadContract.new.call(params)
        result.success? ? Success(result.to_h) : Failure(result.errors.to_h)
      end

      def fetch_resource(params)
        model = params[:model].camelize
        model_object = Object.const_get(model)

        if model_object == Person
          ::Operations::People::Find.new.call(person_id: params[:model_id])
        else
          Success(model_object.find(params[:model_id]))
        end
      end

      def fetch_document(resource, document_id)
        document = resource.documents.where(id: document_id).first

        if document.present?
          Success(document)
        else
          Failure({:message => 'Unable to find Document'})
        end
      end

      def generate_inbox_message(resource, document)
        payload = {
          subjects: [{:id => resource.hbx_id, :type => "Person"}],
          file_name: l10n('hbx_profiles.copy_tax_form_document.subject'),
          id: document.doc_identifier,
          file_content_type: "application/pdf"
        }
        result = Operations::CreateDocumentAndNotifyRecipient.new.call(payload)

        if result.success?
          Success(result.success)
        else
          Failure(result.failure)
        end
      end

      def copy_to_s3(resource, document, validate_params, user)
        return Success(true) unless resource.is_a?(Person) && resource.consumer_role.present? && resource.consumer_role.contact_method.include?("Paper")

        result = ::Operations::Documents::Copy.call({params: validate_params.deep_symbolize_keys, user: user, resource: resource, document: document})
        if result.success?
          Success(result.success)
        else
          Failure(result.failure)
        end
      end
    end
  end
end
