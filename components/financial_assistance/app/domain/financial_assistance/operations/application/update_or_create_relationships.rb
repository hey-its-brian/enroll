# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module FinancialAssistance
  module Operations
    module Application
      # Class for updating or creating relationships between applicants
      # This class is called from the RelationshipsController
      # Once relationships are committed to the database, the unwanted relationships are destroyed
      class UpdateOrCreateRelationships
        include Dry::Monads[:do, :result]

        # @param [ Hash ] {application: application, applicant_id: params[:applicant_id], relative_id: params[:relative_id], relationship_kind: params[:kind]}
        # @return [ FinancialAssistance::Application ] application
        # @return [ String ] error message if any
        def call(params)
          application, applicant_id, relative_id, relationship_kind = yield validate(params)
          predecessor = yield find_applicant_by_id(applicant_id)
          successor = yield find_relative_by_id(relative_id)
          result_hash = yield assign_or_build_relationships(application, predecessor, successor, relationship_kind)
          yield persist(application)
          yield clean_up_unwanted_relationships(result_hash) if result_hash[:relationships_to_destroy].present?

          Success(application)
        end

        private

        def validate(params)
          return Failure(:invalid_params) if params[:application].blank? || params[:applicant_id].blank? || params[:relative_id].blank? || params[:relationship_kind].blank?
          return Failure(:same_predecessor_and_successor) if params[:applicant_id] == params[:relative_id]

          Success([params[:application], params[:applicant_id], params[:relative_id], params[:relationship_kind]])
        end

        def find_applicant_by_id(applicant_id)
          value = FinancialAssistance::Applicant.find(applicant_id)
          value.present? ? Success(value) : Failure("Unable to find Applicant with ID #{applicant_id}.")
        rescue Mongoid::Errors::DocumentNotFound
          Failure("Unable to find Applicant with ID #{applicant_id}.")
        end

        def find_relative_by_id(relative_id)
          value = FinancialAssistance::Applicant.find(relative_id)
          value.present? ? Success(value) : Failure("Unable to find Applicant with ID #{relative_id}.")
        rescue Mongoid::Errors::DocumentNotFound
          Failure("Unable to find Applicant with ID #{relative_id}.")
        end

        def assign_or_build_relationships(application, predecessor, successor, relationship_kind)
          relationships_to_destroy = []
          existing_or_new_relationships = []
          relationship_pairs = [
            [predecessor, successor, relationship_kind],
            [successor, predecessor, ::FinancialAssistance::Relationship::INVERSE_MAP[relationship_kind]]
          ]

          relationship_pairs.each do |applicant, relative, kind|
            result = assign_or_build_relationship(application, applicant, relative, kind)
            existing_or_new_relationships << result[:relationship]
            relationships_to_destroy.concat(result[:relationships_to_destroy])
          end

          Success({ existing_or_new_relationships: existing_or_new_relationships, relationships_to_destroy: relationships_to_destroy })
        end

        def assign_or_build_relationship(application, applicant, relative, kind)
          relationships = application.relationships

          existing_relationship = relationships.where(applicant_id: applicant.id, relative_id: relative.id).first
          return { relationship: existing_relationship, relationships_to_destroy: [] } if existing_relationship.present? && existing_relationship.kind == kind

          if existing_relationship.present?
            if existing_relationship.kind != kind
              relationships_to_destroy = []
              relationships_to_destroy << relationships.where(applicant_id: applicant.id, :id.ne => existing_relationship.id)
              predecessor_relationships_relative_ids = relationships_to_destroy.first.pluck(:relative_id)
              relationships_to_destroy << relationships.where(:applicant_id.in => predecessor_relationships_relative_ids, relative_id: applicant.id)

              existing_relationship.assign_attributes(kind: kind)
              { relationship: existing_relationship, relationships_to_destroy: relationships_to_destroy }
            end
          else
            new_relationship = application.relationships.build(
              {
                kind: kind,
                applicant_id: applicant.id,
                relative_id: relative.id
              }
            )
            { relationship: new_relationship, relationships_to_destroy: [] }
          end
        end

        def persist(application)
          saved = application.save!

          saved ? Success() : Failure(saved)
        rescue StandardError => e
          Failure(e)
        end

        def clean_up_unwanted_relationships(result_hash)
          result = result_hash[:relationships_to_destroy].each(&:destroy_all)
          result ? Success() : Failure(result)
        rescue StandardError => e
          Failure(e)
        end
      end
    end
  end
end
