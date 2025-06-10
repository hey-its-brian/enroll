# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module IndividualMarketEligibility
        # This class is responsible for creating QHP applications.
        class CreateApplication
          include Dry::Monads[:do, :result]

          def call(params)
            # Extract the necessary parameters

            family_id = yield validate(params)
            family = yield find_family(family_id)
            application = yield transform_family(family)
            draft_application = yield build_application(application)
            result = yield persist(draft_application)
            Success(result)
          end

          private

          def validate(params)
            return Failure('family_id is expected in BSON format') unless params[:document_id].is_a?(BSON::ObjectId)

            Success(params[:document_id])
          end

          def find_family(family_id)
            family_find_result = ::Operations::Families::Find.new.call(id: family_id)
            return family_find_result if family_find_result.failure?

            Success(family_find_result.success)
          end

          def transform_family(family)
            contract_result = ::Validators::IndividualMarket::ApplicationContract.new.call(application_attributes(family))
            contract_result.success? ? Success(contract_result.to_h) : Failure(contract_result.errors)
          end

          def application_attributes(family)
            application_attrs = {
              family_id: family.id,
              assistance_year: family.application_applicable_year,
              origin: :migration,
              generation_reason: :manual
            }

            application_attrs.merge!({applicants: applicants_attributes(family)})
            application_attrs
          end

          def applicants_attributes(family)
            family.active_family_members.inject([]) do |members_array, family_member|
              member_attrs_result = ::Operations::IndividualMarket::ParseApplicant.new.call({family_member: family_member})
              members_array << member_attrs_result.success if member_attrs_result.success?
              members_array
            end
          end

          def build_application(application_params)
            application_params[:applicants].each { |a| a.delete(:eligibilities) }
            application = ::IndividualMarket::Application.new(application_params)
            application.applicants.map do |applicant|
              result = build_evidences(applicant)

              return Failure(result.failure) unless result.success?
            end

            build_relationships(application)
            Success(application)
          end

          # Builds evidence records for an applicant
          # @param eligibility [IndividualMarket::Eligibility] The eligibility to build evidences for
          # @param member [FamilyMember] The family member associated with the eligibility
          # @return [void]
          def build_evidences(applicant)
            Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::GenerateEvidences.new.call(applicant: applicant)
          end

          # Builds eligibility records for an applicant
          # @param applicant [IndividualMarket::Applicant] The applicant to build eligibilities for
          # @param eligibilities [Array<Hash>] Array of eligibility parameters
          # @option eligibilities [Symbol] :key The type of eligibility
          # @option eligibilities [String] :title The display title for the eligibility
          # @return [void]
          def build_eligibilities(applicant, eligibilities)
            eligibilities.each do |eligibility|
              eligibility_class = ELIGIBILITY_CLASSES[eligibility[:key]]
              next unless eligibility_class

              applicant.eligibilities.build(eligibility.merge(_type: eligibility_class))
            end
          end

          # Builds relationship records between primary applicant and dependents
          # @param application [IndividualMarket::Application] The application containing the applicants
          # @return [void]
          # @note Relationships are only built for non-primary applicants who have a defined relationship
          #   to the primary applicant through their family member record
          def build_relationships(application)
            primary_applicant = application.primary_applicant

            application.non_primary_applicants.each do |applicant|
              next unless applicant.family_member&.relationship

              relationships_params = {
                source_id: applicant.id,
                relative_id: primary_applicant.id,
                kind: applicant.family_member.relationship
              }

              application.relationships.build(relationships_params)
            end
          end

          def persist(draft_application)
            if draft_application.valid?
              draft_application.state_histories.build(
                event: 'determine',
                from_state: :initial,
                to_state: :determined,
                transition_at: Time.now,
                effective_on: Time.now,
                reason: "creating first QHP application for individual_market eligibility"
              )
              draft_application.save!

              Success(draft_application)
            else
              Failure(draft_application.errors)
            end
          end
        end
      end
    end
  end
end