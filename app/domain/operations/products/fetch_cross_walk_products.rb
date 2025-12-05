# frozen_string_literal: true

module Operations
  module Products
    # This class is to find crosswalk products for IVL enrolled products
    class FetchCrossWalkProducts
      include Dry::Monads[:do, :result]

      def call(params)
        values = yield validate(params)
        crosswalk_product = yield fetch_crosswalk_product(values)
        Success(crosswalk_product)
      end

      private

      def validate(params)
        return Failure('Missing Base Enrollment') if params[:base_enrollment].blank?
        return Failure("Missing Renewal Year") if params[:renewal_year].blank?
        return Failure("Missing Default Renewal Product") if params[:renewal_product].blank?
        Success(params)
      end

      def fetch_crosswalk_product(params)
        base_enrollment = params[:base_enrollment]
        renewal_enrollment_year = params[:renewal_year]
        default_renewal_product = params[:renewal_product]

        # This is a temporary fix for renewal enrollments as the current Data Model does not support cross walk products by county.
        return Success(default_renewal_product) unless [2025, 2026].include?(renewal_enrollment_year)

        cross_walk_product_hios_base_id = fetch_cross_walk_product_hios_base_id(
          base_enrollment&.consumer_role&.rating_address&.county&.capitalize,
          base_enrollment.product.hios_base_id,
          renewal_enrollment_year
        )
        return Success(default_renewal_product) if cross_walk_product_hios_base_id.blank?
        renewal_product = ::BenefitMarkets::Products::HealthProducts::HealthProduct.by_year(renewal_enrollment_year).where(
          { hios_id: "#{cross_walk_product_hios_base_id}-01" }
        ).first
        Success(renewal_product)
      end

      def fetch_cross_walk_product_hios_base_id(county, current_hios_base_id, renewal_year)
        counties = %w[
          Aroostook
          Hancock
          Penobscot
          Piscataquis
          Somerset
          Washington
        ]

        return if counties.exclude?(county)

        crosswalk_mapping_for_year(renewal_year)[current_hios_base_id]
      end

      def crosswalk_mapping_for_year(renewal_year)
        case renewal_year
        when 2025
          {
            '33653ME0560001' => '33653ME0560006',
            '33653ME0560005' => '33653ME0560003'
          }.freeze
        when 2026
          {
            '33653ME0530010' => '33653ME0560006',
            '33653ME0530015' => '33653ME0560003'
          }.freeze
        end
      end
    end
  end
end
