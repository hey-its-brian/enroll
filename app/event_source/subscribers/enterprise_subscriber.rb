# frozen_string_literal: true

module Subscribers
  # Subscriber will receive Enterprise requests like date change
  class EnterpriseSubscriber
    include ::EventSource::Subscriber[amqp: 'enroll.enterprise.events']
    include ResourceRegistryHelper

    subscribe(
      :on_date_advanced
    ) do |delivery_info, _metadata, response|
      logger.info '-' * 100 unless Rails.env.test?

      payload = JSON.parse(response, symbolize_names: true)

      subscriber_logger =
        Logger.new(
          "#{Rails.root}/log/on_date_advanced_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
        )

      subscriber_logger.info "EnterpriseSubscriber, response: #{payload}"
      logger.info "EnterpriseSubscriber payload: #{payload}" unless Rails.env.test?

      parsed_date = Date.parse(payload[:date_of_record])
      if EnrollRegistry.feature_enabled?(:aca_individual_market)
        auto_extend_income_evidence_due_date(parsed_date)
        Operations::Eligibilities::Notices::RequestDocumentReminderNotices.new.call(date_of_record: parsed_date)
      end

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "EnterpriseSubscriber, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      logger.error "EnterpriseSubscriber: errored & acked. error message: #{e.message}, Backtrace: #{e.backtrace}"
      subscriber_logger.error "EnterpriseSubscriber, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    # This method auto extends the income evidence due date for families with outstanding income evidence
    # based on the date provided in the payload and based on the :auto_update_income_evidence_due_on feature flag.
    #
    # @param parsed_date [Date] The date to use for extending the income evidence due date
    #
    # @return [void]
    def auto_extend_income_evidence_due_date(parsed_date)
      return unless FinancialAssistanceRegistry.feature_enabled?(:auto_update_income_evidence_due_on)

      if qhp_application_feature_enabled?
        ::FinancialAssistance::Operations::Evidences::IncomeEvidences::AutoExtendDueDate.new.call(current_due_on: parsed_date)
      else
        ::FinancialAssistance::Operations::Applications::AutoExtendIncomeEvidence.new.call(current_due_on: parsed_date)
      end
    end

    subscribe(
      :on_enroll_enterprise_events
    ) do |delivery_info, _metadata, response|
      logger.info '-' * 100 unless Rails.env.test?

      payload = JSON.parse(response, symbolize_names: true)

      subscriber_logger =
        Logger.new(
          "#{Rails.root}/log/on_enroll_enterprise_events_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
        )

      subscriber_logger.info "EnterpriseSubscriber#on_enroll_enterprise_events, response: #{payload}"
      logger.info "EnterpriseSubscriber#on_enroll_enterprise_events payload: #{payload}" unless Rails.env.test?

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "EnterpriseSubscriber#on_enroll_enterprise_events, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      logger.error "EnterpriseSubscriber#on_enroll_enterprise_events: errored & acked. error message: #{e.message}, Backtrace: #{e.backtrace}"
      subscriber_logger.error "EnterpriseSubscriber#on_enroll_enterprise_events, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end
  end
end
