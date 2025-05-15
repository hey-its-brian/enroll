# frozen_string_literal: true

module Operations
  module BenchmarkProducts
    # This Operation is used to identify rating area and service areas for rating_address of Primary Person of Family
    class IdentifyRatingAndServiceAreas
      include Dry::Monads[:do, :result]

      def call(params)
        # params = { application: application, benchmark_product_model: benchmark_product_model, family: family }
        bpm_params, rating_address = yield find_rating_address(params)
        bpm_params                 = yield find_rating_area(rating_address, bpm_params)
        bpm_params                 = yield find_service_areas(rating_address, bpm_params)
        benchmark_product_model    = yield initialize_benchmark_product_model(bpm_params)

        Success(benchmark_product_model)
      end

      private

      # Retrieves the rating address from the primary applicant in the application
      #
      # @param [Hash] bpm_params The benchmark product model parameters
      # @return [Success<Array<Hash, Object>>] A tuple of updated parameters and the rating address
      # @return [Failure<String>] An error message if rating address is not found
      def fetch_rating_address_from_application(bpm_params)
        rating_address = @application.primary_applicant.rating_address

        if rating_address.present?
          bpm_params[:primary_rating_address_id] = rating_address.id
          Success([bpm_params, rating_address])
        else
          Failure("Unable to find Rating Address for Application with hbx_id: #{@application.hbx_id}")
        end
      end

      def find_rating_address_from_family(bpm_params)
        rating_address = @family.primary_person&.rating_address
        if rating_address.present?
          bpm_params[:primary_rating_address_id] = rating_address.id
          Success([bpm_params, rating_address])
        else
          Failure("Unable to find Rating Address for PrimaryPerson with hbx_id: #{@family.primary_person.hbx_id} of Family with id: #{@family.id}")
        end
      end

      def initialize_address_struct(bpm_params)
        address_struct = OpenStruct.new(
          {
            'county' => bpm_params[:rating_address][:county],
            'state' => bpm_params[:rating_address][:state],
            'zip' => bpm_params[:rating_address][:zip]
          }
        )

        Success([bpm_params, address_struct])
      end

      # Determines and retrieves the rating address based on the data source
      #
      # @param [Hash] params Contains family, application, and benchmark product model
      # @return [Success<Array<Hash, Object>>] A tuple of benchmark product model parameters and rating address
      # @return [Failure<String>] An error message if rating address cannot be determined
      def find_rating_address(params)
        @family = params[:family]
        @application = params[:application]
        bpm_params = params[:benchmark_product_model].to_h

        case bpm_params[:data_source]
        when 'fa_application'
          fetch_rating_address_from_application(bpm_params)
        when 'family'
          find_rating_address_from_family(bpm_params)
        when 'anonymous'
          initialize_address_struct(bpm_params)
        else
          Failure("Unable to find the data source for the given params: #{bpm_params}")
        end
      end

      def find_rating_area(address, bpm_params)
        effective_date = bpm_params[:effective_date]
        rating_area = ::BenefitMarkets::Locations::RatingArea.rating_area_for(address, during: effective_date)

        if rating_area.present?
          bpm_params[:rating_area_id] = rating_area.id
          bpm_params[:exchange_provided_code] = rating_area.exchange_provided_code
          Success(bpm_params)
        else
          Failure(
            "Rating Area not found for effective_date: #{effective_date}, county: #{address.county}, zip: #{address.zip}, state: #{address.state}"
          )
        end
      end

      def find_service_areas(address, bpm_params)
        effective_date = bpm_params[:effective_date]
        service_areas = ::BenefitMarkets::Locations::ServiceArea.service_areas_for(address, during: effective_date)

        if service_areas.present?
          bpm_params[:service_area_ids] = service_areas.map(&:id)
          Success(bpm_params)
        else
          Failure("Service Areas not found for effective_date: #{effective_date}, county: #{address.county}, zip: #{address.zip}, state: #{address.state}")
        end
      end

      def initialize_benchmark_product_model(bpm_params)
        ::Operations::BenchmarkProducts::Initialize.new.call(bpm_params)
      end
    end
  end
end
