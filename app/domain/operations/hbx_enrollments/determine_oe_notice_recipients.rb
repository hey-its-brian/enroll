# frozen_string_literal: true

module Operations
  module HbxEnrollments
    # This class determines the recipients for OE notifications
    # Recipients can either be eligible for OEG or OEQ notifications
    # depending on their enrollment/faa status
    class DetermineOeNoticeRecipients
      include Dry::Monads[:do, :result]

      VALID_OE_NOTICE_TYPES = %w[oeg_oeq oeg oeq].freeze

      # @param [ Hash ] includes key :notice_type with String value
      # @return [ HbxEnrollment ] hbx_enrollment
      def call(params)
        @notice_type      = yield validate(params)
        oe_family_ids     = yield aggregate_recipients
        _send_oe_notices  = yield send_notices(oe_family_ids)

        Success("#{@notice_type} notices sent successfully")
      end

      private

      def validate(params)
        return Failure('Missing Keys.') unless params.key?(:notice_type)
        return Failure('Invalid notice_type Value.') unless params[:notice_type].is_a?(String)
        return Failure('Not a valid NoticeType.') unless VALID_OE_NOTICE_TYPES.include?(params[:notice_type]&.downcase)
        @renewal_year = TimeKeeper.date_of_record.next_year.year
        Success(params[:notice_type].downcase)
      end

      def aggregate_recipients
        eligible_family_ids = []
        eligible_family_ids += fetch_oeg_family_ids if @notice_type.include?('oeg')
        eligible_family_ids += fetch_oeq_family_ids if @notice_type.include?('oeq')

        return Failure("No valid families found for #{@notice_type} notices") if eligible_family_ids.empty?

        Success(eligible_family_ids.uniq)
      end

      def fetch_oeg_family_ids
        if EnrollRegistry.feature_enabled?(:oeg_notice_income_verification_only)
          ::FinancialAssistance::Application.by_year(@renewal_year).income_verification_extension_required.distinct(:family_id)
        else
          ::FinancialAssistance::Application.by_year(@renewal_year).non_determined.distinct(:family_id)
        end
      end

      # Finds eligible families where the tax household group satisfies the following:
      #   1. assistance_year is the renewal year
      #   2. at least one tax household member is marked as is_without_assistance
      #
      # @return [Array] of family ids
      def fetch_oeq_family_ids
        ::Family.where(
          tax_household_groups: {
            :$elemMatch => {
              assistance_year: @renewal_year,
              :'tax_households.tax_household_members.is_without_assistance' => true
            }
          }
        ).distinct(:id)
      end

      def send_notices(eligible_family_ids)
        failures = 0

        eligible_family_ids.each_with_index do |family_id, index|
          family = Family.find_by(id: family_id)
          next unless family.present?

          result = Operations::Notices::IvlOeReverificationTrigger.new.call(family: family)
          if result.success?
            logger.info "Triggered OE event for family_id: #{family_id}, index: #{index}"
          else
            failures += 1
            logger.info "Error: OE event trigger for family_id: #{family_id}, index: #{index} Failed!! due to #{result.failure}"
          end

        rescue StandardError => e
          logger.info "Error triggering OE notice event due to #{e.message} for family_id #{family_id}}"
        end

        logger.info "Triggered #{@notice_type} notices for #{eligible_family_ids.size} families with #{failures} failures"
        Success(true)
      end

      def logger
        @logger ||= Logger.new("#{Rails.root}/log/#{@notice_type}_notice_triggers_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log")
      end
    end
  end
end
