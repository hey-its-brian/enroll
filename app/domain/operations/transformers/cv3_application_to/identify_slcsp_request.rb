# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Transformers
    module Cv3ApplicationTo
      # Cv3Application will be transformed to request payload that is needed for IdentifySlcspWithPediatricDentalCosts.
      class IdentifySlcspRequest
        include Dry::Monads[:do, :result]
        include ::ResourceRegistryHelper

        def call(params)
          cv3_application, fa_application = yield validate(params)
          @family                         = yield find_family(fa_application)
          request_payload                 = yield construct_payload(cv3_application, fa_application)

          Success([@family, request_payload])
        end

        private

        def validate(params)
          cv3_application = params[:mm_application]
          fa_application  = params[:fa_application]

          if cv3_application.is_a?(AcaEntities::MagiMedicaid::Application) && fa_application.is_a?(::FinancialAssistance::Application)
            Success([cv3_application, fa_application])
          else
            Failure("Invalid input: expected AcaEntities::MagiMedicaid::Application and FinancialAssistance::Application")
          end
        end

        def find_family(fa_application)
          return Success('Family object is not needed') if qhp_application_feature_enabled?

          family = fa_application.family

          if family.present?
            Success(family)
          else
            Failure("Family not found for application with hbx_id: #{fa_application.hbx_id}")
          end
        end

        # Constructs the request payload for SLCSP identification
        #
        # @param [AcaEntities::MagiMedicaid::Application] cv3_application The CV3 application entity
        # @param [FinancialAssistance::Application] fa_application The financial assistance application
        # @return [Dry::Monads::Result::Success] Success monad with payload hash
        def construct_payload(cv3_application, fa_application)
          payload = if qhp_application_feature_enabled?
                      {
                        application_id: fa_application.id,
                        application_hbx_id: cv3_application.hbx_id,
                        data_source: 'fa_application',
                        effective_date: cv3_application.aptc_effective_date,
                        households: households(cv3_application, fa_application)
                      }
                    else
                      {
                        application_hbx_id: cv3_application.hbx_id,
                        data_source: 'family',
                        effective_date: cv3_application.aptc_effective_date,
                        family_id: @family.id,
                        households: households(cv3_application, fa_application)
                      }
                    end

          Success(payload)
        end

        def households(cv3_application, fa_application)
          aptc_tax_households = cv3_application.tax_households.select do |thh|
            thh.aptc_members_aged_below_19(cv3_application.aptc_effective_date).present?
          end

          aptc_tax_households.collect do |tax_household|
            {
              household_id: tax_household.hbx_id,
              members: members(fa_application, tax_household.aptc_csr_eligible_members)
            }
          end
        end

        # Formats member information based on application type and member eligibility
        #
        # @param [FinancialAssistance::Application] fa_application The financial assistance application
        # @param [Array<AcaEntities::MagiMedicaid::TaxHouseholdMember>] aptc_csr_eligible_members Members eligible for APTC/CSR
        # @return [Array<Hash>] Formatted member information for the SLCSP request
        def members(fa_application, aptc_csr_eligible_members)
          aptc_csr_eligible_members.collect do |thhm|
            if qhp_application_feature_enabled?
              applicant_reference = thhm.applicant_reference
              next thhm if applicant_reference.blank?

              applicant = fa_application.applicants.where(person_hbx_id: applicant_reference.person_hbx_id).first
              next thhm if applicant.blank?

              { applicant_id: applicant.id, relationship_with_primary: applicant.relation_with_primary }
            else
              family_member = @family.find_family_member_by_person_hbx_id(thhm.applicant_reference&.person_hbx_id)
              next thhm if family_member.blank?

              { family_member_id: family_member&.id, relationship_with_primary: family_member.primary_relationship }
            end
          end
        end
      end
    end
  end
end
