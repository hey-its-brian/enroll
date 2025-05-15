# frozen_string_literal: true

module Operations
  module BenchmarkProducts
    # This class is to identify the type of household. Types: 'adult_only', 'adult_and_child', 'child_only'.
    class IdentifyTypeOfHousehold
      include Dry::Monads[:do, :result]

      def call(benchmark_product_model)
        bpm_params = yield find_age_of_every_member_of_each_household(benchmark_product_model)
        bpm_params = yield identify_type_of_household(bpm_params)
        benchmark_product_model = yield initialize_benchmark_product_model(bpm_params)

        Success([@family, benchmark_product_model, @application])
      end

      private

      # Determines ages for each household member based on the data source
      #
      # @param [BenchmarkProductModel] benchmark_product_model The model containing household data
      # @return [Success<Hash>] Parameters with age information added for each member
      # @return [Failure<String>] Error message if the data source is invalid
      def find_age_of_every_member_of_each_household(benchmark_product_model)
        bpm_params = benchmark_product_model.to_h

        case benchmark_product_model[:data_source]
        when 'fa_application'
          find_member_ages_from_application(bpm_params)
        when 'family'
          find_member_ages_from_family(bpm_params)
        when 'anonymous'
          find_member_ages_from_params(bpm_params)
        else
          Failure("Unable to find the data source for the given params: #{bpm_params}")
        end
      end

      def find_member_ages_from_params(bpm_params)
        bpm_params[:households].each do |household|
          household[:members].each do |member|
            member[:age_on_effective_date] = age_on(member[:date_of_birth], member[:coverage_start_on] || bpm_params[:effective_date])
          end
        end

        Success(bpm_params)
      end

      def age_on(dob, date)
        age = date.year - dob.year
        if date.month < dob.month || (date.month == dob.month && date.day < dob.day)
          age - 1
        else
          age
        end
      end

      # Processes household members from a financial assistance application to determine their ages
      #
      # @param [Hash] bpm_params Benchmark product model parameters
      # @return [Success<Hash>] Parameters with member ages calculated and added
      # @return [Failure<String>] Error message if an applicant cannot be found
      def find_member_ages_from_application(bpm_params)
        bpm_params[:households].each do |household|
          household[:members].each do |member|
            result = fetch_applicant(bpm_params[:application_id], member[:applicant_id])
            return result if result.failure?

            applicant = result.success
            member[:date_of_birth] = applicant.dob
            member[:age_on_effective_date] = applicant.age_on(member[:coverage_start_on] || bpm_params[:effective_date])
          end
        end

        Success(bpm_params)
      end

      # Retrieves a financial assistance applicant by their ID
      #
      # @param [String] application_id The ID of the financial assistance application
      # @param [String] applicant_id The ID of the applicant to fetch
      # @return [Success<Applicant>] The found applicant object
      # @return [Failure<String>] Error message if application or applicant cannot be found
      def fetch_applicant(application_id, applicant_id)
        @application ||= ::FinancialAssistance::Application.find(application_id)
        return Failure("Unable to find application with id: #{application_id}") if @application.blank?

        applicant = @application.applicants.where(id: applicant_id).first
        return Failure("Unable to find Applicant for application with id: #{application_id}, with applicant_id: #{applicant_id}") if applicant.blank?

        Success(applicant)
      end

      def find_member_ages_from_family(bpm_params)
        bpm_params[:households].each do |household|
          household[:members].each do |member|
            result = find_family_member(bpm_params[:family_id], member[:family_member_id])
            return result if result.failure?

            family_member = result.success
            member[:date_of_birth] = family_member.dob
            member[:age_on_effective_date] = family_member.age_on(member[:coverage_start_on] || bpm_params[:effective_date])
          end
        end

        Success(bpm_params)
      end

      def find_family_member(family_id, family_member_id)
        @family ||= Family.where(id: family_id).first
        return Failure("Unable to find Family with family_id: #{family_id}") if @family.blank?

        family_member = @family.family_members.where(id: family_member_id).first
        return Failure("Unable to find FamilyMember for family_id: #{family_id}, with family_member_id: #{family_member_id}") if family_member.blank?

        Success(family_member)
      end

      def identify_type_of_household(bpm_params)
        bpm_params[:households].each do |household|
          household[:type_of_household] = type_of_household(household)
        end

        Success(bpm_params)
      end

      # 'adult_only', 'adult_and_child', 'child_only'
      # If age is less than 19, then a person is considered as Child.
      # If age is greater than or equal to 19, then the person is considered as Adult.
      def type_of_household(household)
        return 'adult_only' if household[:members].all? { |member| member[:age_on_effective_date] >= 19 }
        return 'child_only' if household[:members].all? { |member| member[:age_on_effective_date] < 19 }

        'adult_and_child'
      end

      def initialize_benchmark_product_model(bpm_params)
        ::Operations::BenchmarkProducts::Initialize.new.call(bpm_params)
      end
    end
  end
end
