# frozen_string_literal: true

module Notices
  module IvlNotices
    # This class is used to trigger FRE notice processes.
    # There are three modes available:
    #  1. trigger_notices: This mode triggers generation of the FRE notices for all eligible consumers.
    #  2. notices_report: This mode generates a FRE report indicating if an eligible consumer has or has not received the notice based on the provided date params.
    #  3. failed_validation_report: This mode generates a FRE report indicating if there is an issue with either CV3 transform or CV3 contract validation for each family record that should have an FRE notice generated but did not yet receive one.
    # Three params are passed to this class:
    #  1. mode: Must be one of: trigger_notices, notices_report, failed_validation_report.
    #  2. effective_on: The effective_on date of the renewal enrollments, i.e., the first day of the upcoming year.
    #  3. created_on: The created_on date to check for existing FRE notices. The operation will only take action for consumers who do not have a FRE notice created on or after the created_on date.
    class FreNotice
      include Dry::Monads[:result, :do]
      include EventSource::Command

      attr_reader :mode, :effective_on, :created_on, :file_name, :headers, :logger_name, :logger

      MODES = %w[trigger_notices notices_report failed_validation_report].freeze

      def call(params)
        values = yield validate(params)
        _initialized_values = yield initialize_values(values)
        enrollments = yield fetch_enrollments
        result = yield execute(enrollments)

        Success(result)
      end

      private

      def validate(params)
        return Failure("Missing or incorrect mode. Must be one of: #{MODES}") unless params[:mode].present? && MODES.include?(params[:mode])
        return Failure("Missing effective_on date") unless params[:effective_on].present?
        return Failure("Invalid effective_on date") unless params[:effective_on].is_a?(Date)
        return Failure("Missing created_on date") unless params[:created_on].present?
        return Failure("Invalid created_on date") unless params[:created_on].is_a?(Date)

        Success(params)
      end

      def initialize_values(values)
        @mode = values[:mode]
        @effective_on = values[:effective_on]
        @created_on = values[:created_on]
        @file_name = fetch_file_name
        @headers = fetch_headers
        @logger_name = fetch_logger_name
        @logger = Logger.new(logger_name) unless Rails.env.test?

        Success(true)
      end

      def fetch_enrollments
        enrollments = HbxEnrollment.where(effective_on: effective_on, :aasm_state.in => %w[auto_renewing], :kind.in => %w[individual coverall]).only(:family_id)
        return Failure("No enrollments found for the given effective_on date: #{effective_on}") if enrollments.empty?

        Success(enrollments)
      end

      def query_criteria
        {
          :created_at.gte => created_on,
          subject: /Your Plan Enrollment for #{effective_on.year}/i
        }
      end

      def execute(enrollments)
        family_ids = enrollments.pluck(:family_id).uniq

        case mode
        when 'trigger_notices'
          process_family_ids(family_ids)
          Success("FRE notices triggered successfully. Check #{logger_name} for any errors.")
        when 'notices_report', 'failed_validation_report'
          CSV.open(file_name, 'w+', headers: true) do |csv|
            csv << headers
            process_family_ids(family_ids, csv)
          end
          Success("FRE #{mode} generated successfully. Check #{file_name} for the report. Check #{logger_name} for any errors.")
        end
      end

      def process_family_ids(family_ids, csv = nil)
        family_ids.each_with_index do |family_id, index|
          family = Family.where("id": family_id).first
          person = family&.primary_person
          unless person.present?
            puts "Processing index #{index} | No primary person found for family #{family_id}" unless Rails.env.test?
            next
          end

          message = person.inbox.messages.where(query_criteria).first
          person_hbx_id = person.hbx_id

          if message.present?
            log_message_present(index, family_id, person_hbx_id, csv)
          else
            case mode
            when 'trigger_notices'
              publish_event(index, family_id, person_hbx_id)
            when 'notices_report'
              csv << [family_id, person_hbx_id, false]
            when 'failed_validation_report'
              check_validation_errors(index, family, person_hbx_id, csv)
            end
          end
        rescue StandardError => e
          logger.error { "Unable to process at index #{index} for family #{family_id} | primary hbx id: #{person_hbx_id} due to #{e.message} #{e.backtrace}" } unless Rails.env.test?
        end
      end

      def log_message_present(index, family_id, person_hbx_id, csv)
        case mode
        when 'trigger_notices', 'failed_validation_report'
          p "Processing index #{index} | respective notice already present for family #{family_id} | primary hbx id: #{person_hbx_id}" unless Rails.env.test?
        when 'notices_report'
          p "#{family_id} | #{person_hbx_id} | true" unless Rails.env.test?
          csv << [family_id, person_hbx_id, true]
        end
      end

      # used when mode is 'trigger_notices'
      def publish_event(index, family_id, person_hbx_id)
        p "Processing index #{index} for family #{family_id} | primary hbx id: #{person_hbx_id}" unless Rails.env.test?
        payload = { index: index, family_id: family_id.to_s }
        event = event('events.families.notices.fre_notice_generation.requested', attributes: payload).value!
        event.publish
      end

      # used when mode is 'failed_validation_report'
      def check_validation_errors(index, family, person_hbx_id, csv)
        family_payload = Operations::Transformers::FamilyTo::Cv3Family.new.call(family)
        if family_payload.success?
          family_contract = AcaEntities::Contracts::Families::FamilyContract.new.call(family_payload.value!)
          output =
            if family_contract.success?
              [person_hbx_id, 'success']
            else
              [person_hbx_id, 'failure', family_contract.errors.to_h]
            end
        else
          output = [person_hbx_id, 'failure', family_payload.failure]
        end
        puts "processed index #{index} | family #{family.id} | primary hbx id: #{person_hbx_id}" unless Rails.env.test?
        csv << output
      end

      def fetch_file_name
        # NOTE: there is no output report when mode is 'trigger_notices'
        case mode
        when 'notices_report'
          "#{Rails.root}/ivl_fre_report_#{DateTime.now.strftime('%Y%m%d%H%M%S')}.csv"
        when 'failed_validation_report'
          "#{Rails.root}/ivl_fre_failed_validation_report_#{DateTime.now.strftime('%Y%m%d%H%M%S')}.csv"
        end
      end

      def fetch_headers
        # NOTE: there is no output report when mode is 'trigger_notices'
        case mode
        when 'notices_report'
          %w[family_id hbx_id notice_generated]
        when 'failed_validation_report'
          %w[hbx_id validation_result output]
        end
      end

      def fetch_logger_name
        return if Rails.env.test?

        case mode
        when 'trigger_notices'
          "#{Rails.root}/log/trigger_ivl_fre_notices_error.log"
        when 'notices_report'
          "#{Rails.root}/log/ivl_fre_report_error.log"
        when 'failed_validation_report'
          "#{Rails.root}/log/ivl_fre_failed_validation_report_error.log"
        end
      end
    end
  end
end