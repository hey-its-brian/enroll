# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Subscribers
    module ProcessRequests
      # This Operation processes DetemineSlcsp Request and adds benchmark_product to Cv3Application.
      class DetermineSlcsp
        include Dry::Monads[:do, :result]
        include EventSource::Command
        include ::ResourceRegistryHelper

        def call(params)
          # 1. Initialize Cv3 Application
          # 2. Construct Input Payload for IdentifySlcspWithPediatricDentalCosts
          # 3. Call IdentifySlcspWithPediatricDentalCosts with request_payload
          # 4. Add IdentifySlcspWithPediatricDentalCosts Response to Cv3application
          # 5. Publish the response back

          mm_application           = yield initialize_application(params)
          fa_application           = yield find_application(mm_application)
          @family, request_payload = yield construct_request_payload(fa_application, mm_application)
          benchmark_product        = yield identify_slcsp_with_pediatric_dental_costs(request_payload)
          mm_application           = yield add_benchmark_product_to_application(fa_application, mm_application, benchmark_product)
          event                    = yield build_event(mm_application)
          _published               = yield publish_slcsp_determined_response(event)

          Success(mm_application)
        end

        private

        def initialize_application(params)
          AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(params)
        end

        # Finds a FinancialAssistance::Application by its HBX ID
        # @param [AcaEntities::MagiMedicaid::Application] mm_application the MagiMedicaid application entity
        # @return [Dry::Monads::Result::Success] with the found FinancialAssistance::Application
        # @return [Dry::Monads::Result::Failure] if no application is found with the given HBX ID
        def find_application(mm_application)
          application = ::FinancialAssistance::Application.by_hbx_id(mm_application.hbx_id).first

          if application.present?
            Success(application)
          else
            Failure("FinancialAssistance::Application is not found with given hbx_id: #{mm_application.hbx_id}")
          end
        end

        def construct_request_payload(fa_application, mm_application)
          Operations::Transformers::Cv3ApplicationTo::IdentifySlcspRequest.new.call(
            { fa_application: fa_application, mm_application: mm_application }
          )
        end

        def identify_slcsp_with_pediatric_dental_costs(request_payload)
          Operations::BenchmarkProducts::IdentifySlcspWithPediatricDentalCosts.new.call(request_payload)
        end

        # Retrieves the rating address from either the financial assistance application or family
        # @param [FinancialAssistance::Application] fa_application the financial assistance application
        # @return [Hash] the rating address attributes
        def fetch_rating_address(fa_application)
          if qhp_application_feature_enabled?
            fa_application.primary_applicant.rating_address.attributes
          else
            @family.primary_person.rating_address.attributes
          end
        end

        def add_benchmark_product_to_application(fa_application, mm_application, benchmark_product)
          benchmark_product_hash = {
            effective_date: benchmark_product.effective_date,
            primary_rating_address: fetch_rating_address(fa_application),
            exchange_provided_code: benchmark_product.exchange_provided_code,
            household_group_ehb_premium: benchmark_product.household_group_benchmark_ehb_premium,
            households: benchmark_households(benchmark_product, fa_application)
          }
          mm_app_params = mm_application.to_h
          mm_app_params.merge!(benchmark_product: benchmark_product_hash)
          initialize_application(mm_app_params)
        end

        def benchmark_households(benchmark_product, fa_application)
          benchmark_product.households.collect do |household|
            {
              household_hbx_id: household.household_id,
              type_of_household: household.type_of_household,
              household_ehb_premium: household.household_benchmark_ehb_premium,
              household_health_ehb_premium: household.household_health_benchmark_ehb_premium,
              health_product_reference: health_product_reference(household.health_product_id),
              household_dental_ehb_premium: household.household_dental_benchmark_ehb_premium,
              dental_product_reference: dental_product_reference(household.dental_product_id),
              members: household_members(fa_application, household.members)
            }
          end
        end

        def health_product_reference(product_id)
          product = ::BenefitMarkets::Products::HealthProducts::HealthProduct.find(product_id)
          issuer = product&.issuer_profile
          {
            hios_id: product.hios_id,
            name: product.title,
            active_year: product.active_year,
            is_dental_only: product.dental?,
            metal_level: product.metal_level,
            benefit_market_kind: product.benefit_market_kind.to_s,
            product_kind: product.product_kind.to_s,
            ehb_percent: product.ehb.to_s,
            csr_variant_id: product.csr_variant_id,
            is_csr: product.is_csr?,
            family_deductible: product.family_deductible,
            individual_deductible: product.deductible,
            issuer_profile_reference: { hbx_id: issuer.hbx_id, name: issuer.legal_name, abbrev: issuer.abbrev },
            covers_pediatric_dental_costs: product.covers_pediatric_dental?,
            rating_method: product.rating_method
          }
        end

        def dental_product_reference(product_id)
          return if product_id.blank?

          product = ::BenefitMarkets::Products::DentalProducts::DentalProduct.find(product_id)
          issuer = product&.issuer_profile
          {
            hios_id: product.hios_id,
            name: product.title,
            active_year: product.active_year,
            is_dental_only: product.dental?,
            metal_level: product.metal_level,
            benefit_market_kind: product.benefit_market_kind.to_s,
            product_kind: product.product_kind.to_s,
            ehb_percent: '',
            csr_variant_id: product.csr_variant_id,
            is_csr: product.is_csr?,
            family_deductible: product.family_deductible,
            individual_deductible: product.deductible,
            issuer_profile_reference: { hbx_id: issuer.hbx_id, name: issuer.legal_name, abbrev: issuer.abbrev },
            rating_method: product.rating_method,
            pediatric_dental_ehb: product.ehb_apportionment_for_pediatric_dental
          }
        end

        def household_members(fa_application, members)
          members.collect do |member|
            {
              applicant_reference: applicant_reference(fa_application, member),
              relationship_with_primary: member.relationship_with_primary,
              age_on_effective_date: member.age_on_effective_date
            }
          end
        end

        # Builds a reference hash for an applicant based on the application type
        # @param [FinancialAssistance::Application] fa_application the financial assistance application
        # @param [Object] member the member object containing applicant or family member reference
        # @return [Hash] hash with the member's identifying information
        def applicant_reference(fa_application, member)
          if qhp_application_feature_enabled?
            member = fa_application.applicants.find(member.applicant_id)

            {
              first_name: member.first_name,
              last_name: member.last_name,
              dob: member.dob,
              person_hbx_id: member.person_hbx_id
            }
          else
            family_member = @family.family_members.find(member.family_member_id)

            {
              first_name: family_member.first_name,
              last_name: family_member.last_name,
              dob: family_member.dob,
              person_hbx_id: family_member.hbx_id
            }
          end
        end

        def build_event(mm_application)
          event('events.iap.benchmark_products.slcsp_determined', attributes: mm_application.to_h)
        end

        def publish_slcsp_determined_response(event)
          event.publish

          Success('Successfully published MagiMedicaid Application Entity Hash with Second Lowest Cost Ehb Premium with Pediatric Dental Costs')
        end
      end
    end
  end
end
