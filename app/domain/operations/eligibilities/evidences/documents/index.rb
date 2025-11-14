# app/domain/operations/eligibilities/evidences/documents/index.rb
# frozen_string_literal: true

module Operations
  module Eligibilities
    module Evidences
      module Documents
        # Index operation handles retrieving documents for evidence from applications
        class Index
          include Dry::Monads[:do, :result]

          # Retrieves documents for evidence verification
          #
          # @param params [Hash] parameters for filtering documents
          # @param evidence [Evidence] the evidence record
          # @return [Dry::Monads::Result] Success with result hash or Failure with error message
          def call(params:, evidence:)
            validated_params = yield validate(params, evidence)
            all_applications = yield fetch_applications(validated_params[:family_id])
            filtered_applications = yield filter_applications(all_applications, validated_params[:selected_year])
            years = yield fetch_assistance_years(all_applications)
            document_data = yield fetch_documents_with_app_ids(filtered_applications, evidence)
            pagination = yield paginate_documents(document_data[:documents], validated_params[:page], validated_params[:per_page])

            Success(
              years: years,
              selected_year: validated_params[:selected_year],
              per_page: validated_params[:per_page],
              page: validated_params[:page],
              applications: filtered_applications,
              all_documents: document_data[:documents],
              document_app_map: document_data[:document_app_map],
              uploads: pagination[:items],
              total_pages: pagination[:total_pages],
              bs4: true
            )
          end

          private

          def validate(params, evidence)
            return Failure("Evidence not found") if evidence.blank?
            return Failure("Family ID is required") if params[:family_id].blank?

            validated_params = {
              family_id: params[:family_id],
              selected_year: params[:year].presence,
              per_page: (params[:per_page] || 10).to_i,
              page: (params[:page] || 1).to_i
            }

            Success(validated_params)
          end

          def fetch_assistance_years(applications)
            years = applications.map(&:assistance_year)&.uniq&.compact&.sort&.reverse

            return Failure("No applications found for family") if years&.empty?

            Success(years)
          end

          def fetch_applications(family_id)
            qhp_applications = fetch_qhp_applications(family_id)
            faa_applications = fetch_faa_applications(family_id)
            all_applications = qhp_applications + faa_applications

            Success(all_applications)
          end

          def fetch_qhp_applications(family_id)
            query = ::IndividualMarket::Application.where(family_id: family_id)

            query.to_a
          end

          def fetch_faa_applications(family_id)
            query = ::FinancialAssistance::Application.where(family_id: family_id)

            query.to_a
          end

          def filter_applications(all_applications, selected_year)
            year = selected_year.present? ? selected_year.to_i : Date.today.year

            Success(all_applications.select { |app| app.assistance_year == year })
          end

          # Fetch documents with their application ID mappings
          def fetch_documents_with_app_ids(applications, evidence)
            all_documents = []
            document_app_map = {}
            evidence_key = evidence.key.to_s
            eligibility_key = evidence.eligibility.key
            family_member_id = evidence.eligibility&.eligible&.family_member_id.to_s

            applications.each do |app|
              app_info = { hbx_id: app.hbx_id, assistance_year: app.assistance_year,
                           id: app.id.to_s, type: app.class.to_s}

              applicants = app.applicants.select { |applicant| applicant.family_member_id.to_s == family_member_id }
              applicants.each do |applicant|
                eligibility = applicant.eligibilities.where(key: eligibility_key).first
                next unless eligibility&.evidences

                matching_evidences = eligibility.evidences.select { |ev| ev.key.to_s == evidence_key }

                matching_evidences.each do |ev|
                  next unless ev.documents

                  ev.documents.most_recent_first.each do |doc|
                    all_documents << doc
                    document_app_map[doc.id.to_s] = app_info
                  end
                end
              end
            end

            Success(documents: all_documents, document_app_map: document_app_map)
          end

          def paginate_documents(all_documents, page, per_page)
            uploads = all_documents.slice((page - 1) * per_page, per_page) || []
            total_pages = (all_documents.count / per_page.to_f).ceil

            Success(
              items: uploads,
              total_pages: total_pages
            )
          end
        end
      end
    end
  end
end
