# frozen_string_literal: true

module Operations
  module Eligibilities
    module Evidences
      # ExtendDueDate class handles extending the due date for evidence records
      class ExtendDueDate
        include Dry::Monads[:do, :result]

        # Handles the extension of evidence due date
        #
        # @param params [Hash] extension parameters including evidence, due_on or extension_period, and current_user
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        def call(params)
          _validated_params = yield validate(params)
          extension_result = yield process_due_date_extension
          _persist_result = yield persist_changes

          Success(extension_result)
        end

        private

        def validate(params)
          return Failure("Evidence is required") if params[:evidence].blank?
          return Failure("Application is required") if params[:application].blank?
          return Failure("Current user is required") if params[:current_user].blank?
          return Failure("Due on is required") if params[:due_on].blank? && params[:extension_period].blank?

          @evidence = params[:evidence]
          @application = params[:application]
          @current_user = params[:current_user]
          @due_on = params[:due_on]
          @extension_period = params[:extension_period]

          return Failure("Evidence must be in outstanding state") unless @evidence.current_state == :outstanding
          return Failure("Evidence must have a due date") unless @evidence.due_on.present?

          Success(params)
        end

        # Processes the due date extension based on provided parameters
        #
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        def process_due_date_extension
          extension_result = if @due_on.present?
                               extend_to_specific_date
                             else
                               extend_by_period
                             end

          if extension_result.success?
            duration_string = build_duration_string
            Success("#{@evidence.title} due date extended #{duration_string}")
          else
            Failure("Unable to extend due date")
          end
        rescue StandardError => e
          Rails.logger.error("Evidence ExtendDueDate - Error extending due date: #{e.message}")
          Failure("Due date extension failed: #{e.message}")
        end

        # Extends due date to a specific date
        #
        # @return [Boolean] success status
        def extend_to_specific_date
          due_on = Date.parse(@due_on.to_s)
          update_reason = build_manual_update_reason(due_on)

          @evidence.extend_due_date(
            'extend_due_date',
            due_on,
            @current_user.oim_id,
            update_reason
          )
          Success(@evidence)
        rescue StandardError => e
          Rails.logger.error("Evidence ExtendDueDate - Error extending to specific date: #{e.message}")
          Failure("Extension to specific date failed: #{e.message}")
        end

        # Extends due date by a period (default 30 days)
        #
        # @return [Boolean] success status
        def extend_by_period
          period = @extension_period&.to_i || 30
          current_date = determine_current_date
          due_date = current_date + period.days
          update_reason = build_period_update_reason(period, due_date)

          @evidence.extend_due_date('extend_due_date', due_date, @current_user.oim_id, update_reason)
          Success(@evidence)
        rescue StandardError => e
          Rails.logger.error("Evidence ExtendDueDate - Error extending by period: #{e.message}")
          Failure("Extension by period failed: #{e.message}")
        end

        # Determines the current date based on feature flags
        #
        # @return [Date] current date to use for calculations
        def determine_current_date
          TimeKeeper.date_of_record
        end

        # Builds the update reason for manual date extension
        #
        # @param due_on [Date] the new due date
        # @return [String] formatted update reason
        def build_manual_update_reason(due_on)
          I18n.t('admin.verifications.extend.history_description.manual', date: due_on.strftime('%m/%d/%Y'))
        rescue StandardError
          "Extended due date to #{due_on.strftime('%m/%d/%Y')}"
        end

        # Builds the update reason for period-based extension
        #
        # @param period [Integer] number of days to extend
        # @param due_date [Date] the calculated due date
        # @return [String] formatted update reason
        def build_period_update_reason(period, due_date)
          if EnrollRegistry.feature_enabled?(:verification_due_on_options)
            I18n.t('admin.verifications.extend.history_description.static',
                   day_offset: period - 1,
                   date: due_date.strftime('%m/%d/%Y'))
          else
            "Extended due date to #{due_date.strftime('%m/%d/%Y')}"
          end
        rescue StandardError
          "Extended due date to #{due_date.strftime('%m/%d/%Y')}"
        end

        # Builds the duration string for success message
        #
        # @return [String] formatted duration string
        def build_duration_string
          if EnrollRegistry.feature_enabled?(:verification_due_on_options)
            I18n.t('admin.verifications.extend.success_message.until',
                   date: @evidence.due_on.strftime('%m/%d/%Y'))
          else
            I18n.t('admin.verifications.extend.success_message.period')
          end
        rescue StandardError
          "until #{@evidence.due_on.strftime('%m/%d/%Y')}"
        end

        # Persists all changes to the application
        #
        # @return [Dry::Monads::Result] Success with application or Failure with error message
        def persist_changes
          Success(@application) if @application.save!
        rescue StandardError => e
          Rails.logger.error("Evidence ExtendDueDate - Application save failed: #{e.message}")
          Failure("Application save failed: #{e.message}")
        end
      end
    end
  end
end
