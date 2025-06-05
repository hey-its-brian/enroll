# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  # This operation updates the special enrollment period IDs for HbxEnrollments
  class UpdateHbxEnrollmentSpecialEnrollmentPeriodId
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
                                 .where(:aasm_state.ne => 'shopping',
                                        :enrollment_kind => "special_enrollment",
                                        :special_enrollment_period_id => nil)
      Success(enrollments)
    end

    def process_enrollments(enrollments)
      date = TimeKeeper.date_of_record.strftime("%Y_%m_%d")
      updated_count = 0
      filepath = "#{Rails.root}/updated_enrollments_special_enrollment_period_ids_#{date}.csv"
      CSV.open(filepath, 'w', force_quotes: true) do |csv|
        csv << ['Primary Hbx Id', 'Enrollment Hbx Id', 'Enrollment Kind', 'Enrollment State', 'Special Enrollment Period Id', 'Enrollment Predecessor Hbx Id']

        enrollments.each do |enrollment|

          special_enrollment_period = find_sep(enrollment, 0)
          if special_enrollment_period.present?
            enrollment.update!(special_enrollment_period_id: special_enrollment_period.id)
            csv << [enrollment.family.primary_person.hbx_id, enrollment.hbx_id, enrollment.enrollment_kind, enrollment.aasm_state, special_enrollment_period.id, enrollment.predecessor_enrollment&.hbx_id]
            updated_count += 1
          else
            csv << [enrollment.family.primary_person.hbx_id, enrollment.hbx_id, enrollment.enrollment_kind, enrollment.aasm_state, "No SEP Found", enrollment.predecessor_enrollment&.hbx_id]
          end
        rescue StandardError => e
          Rails.logger.error "Failed to update enrollment #{enrollment.hbx_id}: #{e.message}"

        end
      end
      Success("Successfully updated #{updated_count} enrollments and generated CSV file: #{filepath}")
    end

    def find_sep(enrollment, depth = 0)
      max_depth = 10
      return nil if depth >= max_depth
      family = enrollment.family
      special_enrollment_period = family.special_enrollment_periods.where({
                                                                            :start_on.lte => enrollment.created_at,
                                                                            '$or' => [
        { 'end_on' => nil },
        { 'end_on' => { '$gte' => enrollment.created_at } },
        { 'end_on' => { '$gte' => enrollment.created_at.to_date - 1.day } }
        ]
                                                                          })
                                        .order_by(:effective_on.asc)
                                        .first

      if special_enrollment_period.nil?
        predecessor_enrollment = enrollment.predecessor_enrollment
        special_enrollment_period = find_sep(predecessor_enrollment, depth + 1) if predecessor_enrollment.present?
      end

      special_enrollment_period
    end

  end
end
