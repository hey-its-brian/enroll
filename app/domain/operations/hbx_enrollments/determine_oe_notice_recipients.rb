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
        _send_oe_notices  = yield send_notices

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

      # Aggregates family ids eligible for OEG notices based on the feature flag.
      # When the feature flag is enabled, it fetches families requiring income verification extension.
      # Otherwise, it fetches non-determined families for the renewal year.
      #
      # @return [Array] of family ids
      def fetch_oeg_family_ids
        if EnrollRegistry.feature_enabled?(:oeg_notice_income_verification_only)
          ::FinancialAssistance::Application.by_year(@renewal_year).income_verification_extension_required.distinct(:family_id)
        else
          ::FinancialAssistance::Application.by_year(@renewal_year).non_determined.distinct(:family_id)
        end
      end

      # Finds eligible families for OEQ notices. The families must have at least one applicant
      # who is eligible for coverage in the renewal year based on their individual market determination
      # for a IndividualMarket::Application.
      #
      # @return [Array] of family ids
      def fetch_oeq_family_ids
        ::IndividualMarket::Application.where(
          current_state: :determined,
          assistance_year: @renewal_year,
          :'applicants.eligibilities' => {
            :$elemMatch => {
              :'determinations._type' => 'Eligibilities::V3::Determinations::IndividualMarketDetermination',
              :'determinations.is_eligible' => true
            }
          }
        ).distinct(:family_id)
      end

      # Sends notices based on the notice type specified.
      #
      # @return [Dry::Monads::Result] Success with message if notices are sent successfully
      def send_notices
        case @notice_type
        when 'oeg_oeq'
          trigger_oeg_notices
          trigger_oeq_notices
        when 'oeg'
          trigger_oeg_notices
        when 'oeq'
          trigger_oeq_notices
        end

        Success("#{@notice_type} notices processed successfully. Please see logger for details.")
      end

      # Triggers OEG notices for eligible families.
      # It checks if the family requires income verification extension based on the feature flag.
      #
      # @return [void]
      def trigger_oeg_notices
        fetch_oeg_family_ids.each do |family_id|
          family = Family.find(family_id)
          logger.info "Triggering OEG notice for Family ID: #{family_id}"

          most_recent_renewal_faa = ::FinancialAssistance::Application.where(
            family_id: family_id, assistance_year: @renewal_year
          ).order_by(created_at: -1).limit(1).first

          if EnrollRegistry.feature_enabled?(:oeg_notice_income_verification_only)
            logger.info "Family ID: #{family_id} - Checking income verification extension requirement."
            if most_recent_renewal_faa.income_verification_extension_required?
              result = ::Operations::Notices::IvlOeReverificationTrigger.new.call({ family: family, notice_type: 'oeg' })
              if result.success?
                logger.info "Successfully triggered OEG notice for Family ID: #{family_id}, FAA ID: #{most_recent_renewal_faa.id}"
              else
                logger.error "Failed to trigger OEG notice for Family ID: #{family_id}, FAA ID: #{most_recent_renewal_faa.id}, Error: #{result.failure}"
              end
            else
              logger.info "Family ID: #{family_id} - Skipping OEG notice for application #{most_recent_renewal_faa.id} as the state #{most_recent_renewal_faa.aasm_state} is not income_verification_extension_required."
            end
          elsif most_recent_renewal_faa.non_determined?
            result = ::Operations::Notices::IvlOeReverificationTrigger.new.call({ family: family, notice_type: 'oeg' })
            if result.success?
              logger.info "Successfully triggered OEG notice for Family ID: #{family_id}, FAA ID: #{most_recent_renewal_faa.id}"
            else
              logger.error "Failed to trigger OEG notice for Family ID: #{family_id}, FAA ID: #{most_recent_renewal_faa.id}, Error: #{result.failure}"
            end
          else
            logger.info "Family ID: #{family_id} - Skipping OEG notice for application #{most_recent_renewal_faa.id} as the state #{most_recent_renewal_faa.aasm_state} is not non_determined."
          end
        rescue StandardError => e
          logger.error "Exception occurred while processing Family ID: #{family_id}, Error: #{e.message}, Backtrace: #{e.backtrace.join("\n")}"
        end
      end

      # Triggers OEQ notices for eligible families.
      #
      # @return [void]
      def trigger_oeq_notices
        fetch_oeq_family_ids.each do |family_id|
          logger.info "Triggering OEQ notice for Family ID: #{family_id}"
          family = Family.find(family_id)
          result = Operations::Notices::IvlOeReverificationTrigger.new.call({ family: family, notice_type: 'oeq' })

          if result.success?
            logger.info "Successfully triggered OEQ notice for Family ID: #{family_id}"
          else
            logger.error "Failed to trigger OEQ notice for Family ID: #{family_id}, Error: #{result.failure}"
          end
        rescue StandardError => e
          logger.error "Exception occurred while processing Family ID: #{family_id}, Error: #{e.message}, Backtrace: #{e.backtrace.join("\n")}"
        end
      end

      # Initializes a logger for recording notice trigger events.
      #
      # @return [Logger] the logger instance
      def logger
        @logger ||= Logger.new("#{Rails.root}/log/#{@notice_type}_notice_triggers_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log")
      end
    end
  end
end
