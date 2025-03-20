# frozen_string_literal: true

module Operations
  module Migrations
    module TaxHouseholdEnrollments
      # This class creates tax household enrollments which are missing for reinstated enrollments
      class CreateForReinstatedEnrollments
        include Dry::Monads[:do, :result]

        # Initiates the process of fetching enrollments and creating tax household enrollments for missing cases
        #
        # @param [Hash] params the input parameters
        # @option params [Integer] :year the year for filtering enrollments
        # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure] the result of the operation
        def call(params)
          valid_params = yield validate(params)
          enrollments  = yield fetch_eligible_enrollments(valid_params)
          result    = yield create_thh_enrs(enrollments)

          Success(result)
        end

        private

        # Validates the input parameters
        #
        # @param [Hash] params the input parameters
        # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure] success if parameters are valid, otherwise failure
        def validate(params)
          return Failure('Pass in year') if params[:year].blank?

          Success(params)
        end

        # Fetches eligible enrollments
        #
        # @param [Hash] params the input parameters
        # @option params [Integer] :year the year for filtering enrollments
        # @return [Dry::Monads::Result::Success<Array<HbxEnrollment>>] success with a list of eligible enrollments
        def fetch_eligible_enrollments(params)
          eligible_states = HbxEnrollment::ENROLLED_STATUSES + HbxEnrollment::TERMINATED_STATUSES + ['coverage_canceled']
          Success(HbxEnrollment.all.with_aptc.by_year(params[:year].to_i).by_health.where(:aasm_state.in => eligible_states).order(:created_at.asc))
        end

        # Creates tax household enrollments and generates a CSV report
        #
        # @param [Array<HbxEnrollment>] enrollments the list of enrollments to process
        # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure] success with a message if successful
        def create_thh_enrs(enrollments)
          return Success('No enrollments found.') if enrollments.blank?

          csv_file = "#{Rails.root}/reinstated_enrollments_with_thh_enrs_creation_report.csv"
          CSV.open(csv_file, 'w', force_quotes: true) do |csv|
            write_csv_headers(csv)
            enrollments.no_timeout.each { |enrollment| process_enrollment(enrollment, csv) }
          end

          Success(
            "Successfully created missing tax household enrollments for APTC enrollments. Please check the report: #{csv_file} for more details."
          )
        end

        # Writes headers to the CSV file
        #
        # @param [CSV] csv the CSV object
        # @return [void]
        def write_csv_headers(csv)
          csv << %w[
            primary_hbx_id
            enrollment_hbx_id
            applied_aptc_amount
            enrollment_created_at
            aasm_state
            tax_household_enrollments_present?
          ]
        end

        # Processes a single enrollment and appends data to the CSV
        #
        # @param [HbxEnrollment] enrollment the enrollment to process
        # @param [CSV] csv the CSV object
        # @return [void]
        def process_enrollment(enrollment, csv)
          return unless reinstated?(enrollment)
          return if enrollment.tax_household_enrollments.present?

          create_missing_thh_enrollments(enrollment)
          write_csv_row(enrollment, csv)
        rescue StandardError => e
          log_error(enrollment, csv, e)
        end

        # Checks if the enrollment is reinstated
        #
        # @param [HbxEnrollment] enrollment the enrollment to check
        # @return [Boolean] true if the enrollment is reinstated, false otherwise
        def reinstated?(enrollment)
          enrollment.workflow_state_transitions.map(&:to_state).include?("coverage_reinstated")
        end

        # Creates missing tax household enrollments
        #
        # @param [HbxEnrollment] enrollment the enrollment to process
        # @return [void]
        def create_missing_thh_enrollments(enrollment)
          pre_enr = enrollment.predecessor_enrollment
          return unless pre_enr

          if pre_enr.tax_household_enrollments.blank? && pre_enr.predecessor_enrollment&.tax_household_enrollments.present?
            clone_thh_enrollments(pre_enr.predecessor_enrollment, pre_enr)
          elsif pre_enr.tax_household_enrollments.present? && enrollment.tax_household_enrollments.blank?
            clone_thh_enrollments(pre_enr, enrollment)
          end
        end

        # Clones tax household enrollments from one enrollment to another
        #
        # @param [HbxEnrollment] from_enrollment the source enrollment
        # @param [HbxEnrollment] to_enrollment the target enrollment
        # @return [void]
        def clone_thh_enrollments(from_enrollment, to_enrollment)
          TaxHouseholdEnrollment.by_enrollment_id(from_enrollment.id).each do |thhe|
            new_thhe = thhe.build_tax_household_enrollment_for(to_enrollment)
            new_thhe.save!
          end
        end

        # Writes a single row to the CSV file
        #
        # @param [HbxEnrollment] enrollment the enrollment to log
        # @param [CSV] csv the CSV object
        # @return [void]
        def write_csv_row(enrollment, csv)
          csv << [
            enrollment.family.primary_person.hbx_id,
            enrollment.hbx_id,
            enrollment.applied_aptc_amount,
            enrollment.created_at,
            enrollment.aasm_state,
            enrollment.tax_household_enrollments.present?
          ]
        end

        # Logs an error to the CSV file
        #
        # @param [HbxEnrollment] enrollment the enrollment that caused the error
        # @param [CSV] csv the CSV object
        # @param [StandardError] error the exception raised
        # @return [void]
        def log_error(enrollment, csv, error)
          csv << [
            enrollment.family.primary_person&.hbx_id,
            enrollment.hbx_id,
            enrollment.applied_aptc_amount,
            enrollment.created_at,
            enrollment.aasm_state,
            enrollment.tax_household_enrollments.present?,
            "Error: #{error.message}"
          ]
        end
      end
    end
  end
end
