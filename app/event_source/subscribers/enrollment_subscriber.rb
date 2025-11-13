# frozen_string_literal: true

module Subscribers
  # Subscriber will receive request payload from EA to generate a renewal draft application
  class EnrollmentSubscriber
    include ::EventSource::Subscriber[amqp: 'enroll.individual.enrollments']
    include ::ResourceRegistryHelper

    subscribe(:on_enrollment_saved) do |delivery_info, _metadata, response|
      subscriber_logger = subscriber_logger_for(:on_enrollment_saved)
      payload = JSON.parse(response, symbolize_names: true)
      pre_process_message(subscriber_logger, payload)

      # Add subscriber operations below this line
      if qhp_application_feature_enabled?
        handle_enrollment_saved(subscriber_logger, payload)
      else
        redetermine_family_eligibility(subscriber_logger, payload)
      end

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "EnrollmentSubscriber, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
    #   logger.info "EnrollmentSubscriber: errored & acked. Backtrace: #{e.backtrace}"
      subscriber_logger.error "EnrollmentSubscriber, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    subscribe(:on_coverage_selected) do |delivery_info, _metadata, response|
      subscriber_logger = subscriber_logger_for(:on_coverage_selected)
      payload = JSON.parse(response, symbolize_names: true)
      pre_process_message(subscriber_logger, payload)

      # Add subscriber operations below this line
      # create_grants(payload)

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "EnrollmentSubscriber, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      subscriber_logger.error "EnrollmentSubscriber, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    subscribe(:on_enroll_individual_enrollments) do |delivery_info, _metadata, response|
      subscriber_logger = subscriber_logger_for(:on_enroll_individual_enrollments)
      payload = JSON.parse(response, symbolize_names: true)

      subscriber_logger.info "EnrollmentSubscriber#on_enroll_individual_enrollments, response: #{payload}"

      ack(delivery_info.delivery_tag)
    rescue StandardError, SystemStackError => e
      subscriber_logger.error "EnrollmentSubscriber#on_enroll_individual_enrollments, payload: #{payload}, error message: #{e.message}, backtrace: #{e.backtrace}"
      subscriber_logger.error "EnrollmentSubscriber#on_enroll_individual_enrollments, ack: #{payload}"
      ack(delivery_info.delivery_tag)
    end

    def handle_enrollment_saved(subscriber_logger, payload)
      result = ::Operations::HbxEnrollments::OnSave.new.call(payload)

      if result.success?
        data = result.value!
        reconciliation = data[:reconciliation_result]
        subscriber_logger.info(
          "EnrollmentSubscriber#handle_enrollment_saved, #{data[:enrollment]&.hbx_id} processed" +
          (if reconciliation[:status] == :success
             " with reconciliation on application #{reconciliation[:application]&.hbx_id}"
           else
             " (reconciliation skipped because #{reconciliation[:message]})"
           end)
        )
      else
        subscriber_logger.error "EnrollmentSubscriber#handle_enrollment_saved, failed to update application evidences for enrollment #{payload[:gid]}, error: #{result.failure}"
        Rails.logger.error "EnrollmentSubscriber#handle_enrollment_saved, failed to update application evidences for enrollment #{payload[:gid]}, error: #{result.failure}"
      end
    end

    def redetermine_family_eligibility(subscriber_logger, payload)
      enrollment = GlobalID::Locator.locate(payload[:gid])
      return if enrollment.shopping? || Rails.env.test?

      family = enrollment.family
      assistance_year = enrollment.effective_on.year

      if HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES.include?(enrollment.aasm_state)
        family.update_verification_types
        application = fetch_application(enrollment, assistance_year)
        subscriber_logger.info "EnrollmentSubscriber, redetermine_family_eligibility for enrollment #{enrollment.hbx_id} with the application #{application&.hbx_id}"
        application&.enrolled_with(enrollment) if enrollment.health?
      end

      family.update_due_dates_on_vlp_docs_and_evidences(assistance_year)
      ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
    end

    private

    def fetch_application(enrollment, assistance_year)
      application = if EnrollRegistry.feature_enabled?(:temporary_configuration_enable_multi_tax_household_feature)
                      thhe = TaxHouseholdEnrollment.where(enrollment_id: enrollment.id).first
                      application_hbx_id = thhe&.tax_household&.tax_household_group&.application_hbx_id
                      ::FinancialAssistance::Application.where(hbx_id: application_hbx_id).first
                    end

      return application if application.present?

      FinancialAssistance::Application.newest_determined_by_family_and_year(enrollment.family.id, assistance_year).first
    end

    def pre_process_message(subscriber_logger, payload)
    #   logger.info '-' * 100 unless Rails.env.test?
      subscriber_logger.info "EnrollmentSubscriber, response: #{payload}"
    #   logger.info "EnrollmentSubscriber payload: #{payload}" unless Rails.env.test?
    end

    def subscriber_logger_for(event)
      Logger.new(
        "#{Rails.root}/log/#{event}_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
      )
    end
  end
end
