# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  # This operation removes the Special Enrollment Period IDs for HbxEnrollments that were not created during an active SEP.
  class RemoveHbxEnrollmentSpecialEnrollmentPeriod
    include Dry::Monads[:do, :result]

    def call(params)
      year        = yield validate(params)
      enrollments = yield fetch_enrollments(year)
      process_enrollments(enrollments)
    end

    private

    def validate(params)
      return Failure("Missing Year") if params[:year].blank?
      Success(params[:year].to_i)
    end

    def fetch_enrollments(year)
      enrollments = HbxEnrollment.by_year(year)
                                 .where(:aasm_state.ne => "shopping", :predecessor_enrollment_id.ne => nil, :special_enrollment_period_id.ne => nil)
      Success(enrollments)
    end

    def process_enrollments(enrollments)
      date = TimeKeeper.date_of_record.strftime("%Y_%m_%d")
      updated_count = 0
      filepath = Rails.root.join("removed_enrollment_special_enrollment_period_ids_#{date}.csv")
      CSV.open(filepath, 'w', force_quotes: true) do |csv|
        csv << ['Primary Hbx Id', 'Enrollment Hbx Id', 'Enrollment Kind', 'Enrollment State', 'Special Enrollment Period Id', 'Enrollment Predecessor Hbx Id']
        enrollments.each do |enrollment|
          valid_sep = valid_sep?(enrollment)
          begin
            if !valid_sep || (valid_sep && (coinciding_applications?(enrollment) || reinstated_enrollment?(enrollment)))
              enrollment.update!(special_enrollment_period_id: nil)
              updated_count += 1
              csv << csv_row(enrollment, enrollment.special_enrollment_period_id)
            end
          rescue StandardError => e
            Rails.logger.error "Failed to update enrollment #{enrollment.hbx_id}: #{e.message}"
          end
        end
      end
      Success("Successfully updated #{updated_count} enrollments and generated CSV file: #{filepath}")
    end

    def csv_row(enrollment, sep_id)
      [
        enrollment.family.primary_person.hbx_id,
        enrollment.hbx_id,
        enrollment.enrollment_kind,
        enrollment.aasm_state,
        sep_id,
        enrollment.predecessor_enrollment&.hbx_id
      ]
    end

    def valid_sep?(enrollment)
      special_enrollment_period = enrollment.special_enrollment_period
      return false unless special_enrollment_period.present?
      special_enrollment_period.start_on <= enrollment.created_at && (special_enrollment_period.end_on.nil? || special_enrollment_period.end_on >= enrollment.created_at || special_enrollment_period.end_on >= enrollment.created_at.to_date - 1.day)
    end

    def coinciding_applications?(enrollment)
      family = enrollment.family
      applications = ::FinancialAssistance::Application.determined.where(
        family_id: family.id,
        submitted_at: enrollment.created_at.beginning_of_day..enrollment.created_at.end_of_day
      )
      # check if any enrollments were created within 30 seconds of the application determination
      enrollment_transition_at = enrollment.workflow_state_transitions.min_by(&:created_at)&.transition_at
      applications.any? do |application|
        transition_timestamp = application.workflow_state_transitions.where(to_state: "determined").first&.transition_at
        transition_timestamp && enrollment_transition_at &&
          (transition_timestamp..transition_timestamp + 30.seconds).cover?(enrollment_transition_at)
      end
    end

    def reinstated_enrollment?(enrollment)
      enrollment.workflow_state_transitions.any? do |transition|
        transition.from_state == 'shopping' && transition.to_state == "coverage_reinstated"
      end
    end
  end
end