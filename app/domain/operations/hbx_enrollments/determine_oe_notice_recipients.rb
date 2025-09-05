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
        @notice_type                     = yield validate(params)
        faa_application_families         = yield fetch_faa_application_families
        oe_family_ids                    = yield aggregate_recipients(faa_application_families)
        _send_oe_notices                 = yield send_notices(oe_family_ids)

        Success("#{@notice_type} notices sent successfully")
      end

      private

      def validate(params)
        return Failure('Missing Keys.') unless params.key?(:notice_type)
        return Failure('Invalid notice_type Value.') unless params[:notice_type].is_a?(String)
        return Failure('Not a valid NoticeType.') unless VALID_OE_NOTICE_TYPES.include?(params[:notice_type]&.downcase)

        Success(params[:notice_type].downcase)
      end

      def fetch_faa_application_families
        @renewal_year = TimeKeeper.date_of_record.next_year.year
        faa_application_families = ::FinancialAssistance::Application.by_year(@renewal_year).distinct(:family_id)

        Success(faa_application_families)
      rescue StandardError => e
        logger.error "Error fetching FAA application families: #{e.message}"
        Failure("Error fetching FAA application families: #{e.message}")
      end

      def aggregate_recipients(faa_application_families)
        families = []

        families += fetch_oeg_family_ids(faa_application_families) if @notice_type.include?('oeg')
        families += fetch_oeq_family_ids(faa_application_families) if @notice_type.include?('oeq')

        return Failure("No valid families found for #{@notice_type} notices") if families.empty?

        Success(families)
      end

      def fetch_oeg_family_ids(faa_application_families)
        oeg_family_ids = if EnrollRegistry.feature_enabled?(:oeg_notice_income_verification_only)
                           ::FinancialAssistance::Application.by_year(@renewal_year).income_verification_extension_required.distinct(:family_id)
                         else
                           faa_application_families - ::FinancialAssistance::Application.determined.by_year(@renewal_year).distinct(:family_id)
                         end

        HbxEnrollment.active.enrolled.current_year.where(:family_id.in => oeg_family_ids).distinct(:family_id)
      end

      def fetch_oeq_family_ids(faa_application_families)
        HbxEnrollment.active.enrolled.current_year.where(:family_id.nin => faa_application_families).distinct(:family_id)
      end

      def send_notices(families)
        failures = 0

        families.each_with_index do |family_id, index|
          family = Family.find_by(id: family_id)
          next unless family.present?

          result = Operations::Notices::IvlOeReverificationTrigger.new.call(family: family)

          if result.success?
            puts "Triggered OE event for family_id: #{family_id}, index: #{index}"
            logger.info "Triggered OE event for family_id: #{family_id}, index: #{index}"
          else
            failures += 1
            puts "Error: OE event trigger for family_id: #{family_id}, index: #{index} Failed!! due to #{result.failure}"
            logger.info "Error: OE event trigger for family_id: #{family_id}, index: #{index} Failed!! due to #{result.failure}"
          end

        rescue StandardError => e
          puts "Error triggering OE notice event due to #{e.message} for family_id #{family_id}}"
          logger.info "Error triggering OE notice event due to #{e.message} for family_id #{family_id}}"
        end

        puts "Triggered #{@notice_type} notices for #{families.size} families with #{failures} failures"
        Success(true)
      end

      def logger
        @logger ||= Logger.new("#{Rails.root}/log/#{@notice_type}_notice_triggers_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log")
      end
    end
  end
end
