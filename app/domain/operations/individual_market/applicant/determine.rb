# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    module Applicant
      # This operation is used to determine an applicant's individual market eligibility
      class Determine
        include Dry::Monads[:do, :result, :try]

        # @param [IndividualMarket::Application] application
        # @param [IndividualMarket::Applicant] applicant
        # @return [Dry::Monads::Result]
        def call(params)
          application, applicant = yield validate(params)
          _eligibility = yield build_determinations(application, applicant)
          _qhp_determination = yield determine_qhp_eligibility(application, applicant)
          _csr_determination = yield determine_csr_eligibility(applicant)
          Success(applicant)
        end

        # Validates the parameters
        # @param [Hash] params
        # @return [Dry::Monads::Result]
        def validate(params)
          application = params[:application]
          applicant = params[:applicant]
          return Failure("Invalid application type. Expected IndividualMarket::Application.") unless application.is_a?(::IndividualMarket::Application)
          return Failure("Invalid applicant type. Expected IndividualMarket::Applicant.") unless applicant.is_a?(::IndividualMarket::Applicant)
          return Failure("Applicant #{applicant.id} does not have an individual market eligibility") unless applicant.individual_market_eligibility.present?
          Success([application, applicant])
        end

        def build_determinations(_application, applicant)
          applicant.individual_market_eligibility.build_individual_market_determination
          applicant.individual_market_eligibility.build_csr_determination
          applicant.individual_market_eligibility.save!

          Success(applicant.individual_market_eligibility.reload)
        end

        # Determines the QHP eligibility
        # @param [IndividualMarket::Application] application
        # @param [IndividualMarket::Applicant] applicant
        # @return [Dry::Monads::Result]
        def determine_qhp_eligibility(application, applicant)
          @qhp_determination = applicant.individual_market_eligibility.qhp_determination
          generate_applying_coverage_basis(applicant)
          @applying_coverage = applicant.is_applying_coverage
          if @applying_coverage
            generate_incarceration_basis(applicant)
            generate_is_alive_basis(applicant)
            generate_state_resident_basis(applicant, application)
            generate_lawfully_present_in_us_basis(applicant)
          end

          Try do
            @qhp_determination.determine_eligibility
          end.or(Failure("Failed to determine QHP eligibility for applicant #{applicant.id}"))
        end

        # Generates the incarceration basis
        # @param [IndividualMarket::Applicant] applicant
        # @return [Dry::Monads::Result]
        def generate_incarceration_basis(applicant)
          @qhp_determination.bases.build({basis_kind: 'not_incarcerated', is_satisfied: !applicant.demographics.is_incarcerated})
        end

        # Generates the applying coverage basis
        # @param [IndividualMarket::Applicant] applicant
        # @return [Dry::Monads::Result]
        def generate_applying_coverage_basis(applicant)
          @qhp_determination.bases.build({basis_kind: 'applying_coverage', is_satisfied: applicant.is_applying_coverage})
        end

        # Generates the is alive basis
        # @param [IndividualMarket::Applicant] applicant
        # @return [Dry::Monads::Result]
        def generate_is_alive_basis(_applicant)
          @qhp_determination.bases.build({basis_kind: 'is_alive', is_satisfied: true})
        end

        # Generates the state resident basis
        # @param [IndividualMarket::Applicant] applicant
        # @param [IndividualMarket::Application] application
        # @return [Dry::Monads::Result]
        def generate_state_resident_basis(applicant, application)
          state_resident = applicant.is_state_resident? || adult_family_member_is_state_resident?(application.applicants)
          @qhp_determination.bases.build({basis_kind: 'state_resident', is_satisfied: state_resident})
        end

        # Determines if an adult family member is a state resident
        # @param [Array<IndividualMarket::Applicant>] applicants
        # @return [Boolean]
        def adult_family_member_is_state_resident?(applicants)
          applicants.any? do |applicant|
            applicant.is_state_resident? && age_on_next_effective_date(applicant.demographics.dob) >= 19
          end
        end

        # Calculates the age on the next effective date
        # @param [Date] dob
        # @return [Integer]
        def age_on_next_effective_date(dob)
          today = TimeKeeper.date_of_record
          age_on = today.day <= 15 ? today.end_of_month + 1.day : (today + 1.month).end_of_month + 1.day
          age_on.year - dob.year - ((age_on.month > dob.month || (age_on.month == dob.month && age_on.day >= dob.day)) ? 0 : 1)
        end

        # Generates the lawfully present in US basis
        # @param [IndividualMarket::Applicant] applicant
        # @return [Dry::Monads::Result]
        def generate_lawfully_present_in_us_basis(applicant)
          is_lawfully_present = !applicant.demographics.citizen_status.blank? && !ConsumerRole::INELIGIBLE_CITIZEN_VERIFICATION.include?(applicant.demographics.citizen_status)
          @qhp_determination.bases.build({basis_kind: 'lawfully_present_in_us', is_satisfied: is_lawfully_present})
        end

        # Determines the CSR eligibility
        # @param [IndividualMarket::Applicant] applicant
        # @return [Dry::Monads::Result]
        def determine_csr_eligibility(applicant)
          @csr_determination = applicant.individual_market_eligibility.csr_determination
          generate_ai_na_attested_basis(applicant) if @applying_coverage

          Try do
            @csr_determination.update(csr_type: 'csr_limited')
            @csr_determination.determine_individual_market_eligibility if @applying_coverage
            applicant.individual_market_eligibility.save!
          end.or(Failure("Failed to determine CSR eligibility for applicant #{applicant.id}"))
        end

        # Generates the AI/NA attested basis
        # @param [IndividualMarket::Applicant] applicant
        # @return [Dry::Monads::Result]
        def generate_ai_na_attested_basis(applicant)
          @csr_determination.bases.build({basis_kind: 'ai_na_attested', is_satisfied: applicant.demographics.indian_tribe_member})
        end
      end
    end
  end
end