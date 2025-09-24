# frozen_string_literal: true

module Operations
  module HbxEnrollments
    # Updates FAA and QHP application evidences based on enrollment changes
    class UpdateApplicationEvidences
      include Dry::Monads[:do, :result]

      # Main entry point for updating application evidences based on enrollment changes
      def call(params)
        enrollment = yield validate(params)
        application = yield fetch_related_application(enrollment)
        _result = yield update_applicants(application, enrollment)

        recreate_family_eligibility_determination(enrollment)
      end

      private

      # Validates input parameters and enrollment state
      #
      # @param params [Hash] Input parameters containing enrollment GID
      # @option params [String] :gid GlobalID of the enrollment
      #
      # @return [Dry::Monads::Success<HbxEnrollment>, Dry::Monads::Failure<String>]
      #   Success with enrollment or Failure with error message
      #
      # @example Valid enrollment
      #   validate(gid: "gid://enroll/HbxEnrollment/123")
      #   # => Success(#<HbxEnrollment>)
      #
      # @example Invalid cases
      #   validate(gid: nil)
      #   # => Failure("Missing enrollment")
      #
      #   validate(gid: shopping_enrollment_gid)
      #   # => Failure("Enrollment should not be in Shopping State")
      def validate(params)
        enrollment = GlobalID::Locator.locate(params[:gid])

        return Failure('Missing enrollment') unless enrollment
        return Failure('Enrollment should not be in Shopping State') if enrollment.shopping?
        return Failure(invalid_state_message) unless valid_enrollment_state?(enrollment)

        Success(enrollment)
      end

      # Checks if enrollment is in a valid state for evidence updates
      #
      # Valid states are those where the member is actively enrolled or renewing,
      # as defined by {HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES}.
      #
      # @param enrollment [HbxEnrollment] The enrollment to validate
      #
      # @return [Boolean] True if enrollment state allows evidence updates
      #
      # @example Valid states
      #   enrollment.aasm_state = 'coverage_selected'
      #   valid_enrollment_state?(enrollment) # => true
      #
      #   enrollment.aasm_state = 'auto_renewing'
      #   valid_enrollment_state?(enrollment) # => true
      #
      # @example Invalid states
      #   enrollment.aasm_state = 'shopping'
      #   valid_enrollment_state?(enrollment) # => false
      def valid_enrollment_state?(enrollment)
        HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES.include?(enrollment.aasm_state)
      end

      # Generates error message for invalid enrollment states
      def invalid_state_message
        valid_states = HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES.join(', ')
        "Enrollment must be in one of these states: #{valid_states}"
      end

      # Fetches the financial assistance application related to the enrollment
      #
      # Uses a two-stage approach:
      # 1. First attempts to find application through tax household enrollment relationship
      # 2. Falls back to finding the latest determined application for the enrollment year
      #
      # @param enrollment [HbxEnrollment] The enrollment to find application for
      #
      # @return [Dry::Monads::Success<FinancialAssistance::Application>, Dry::Monads::Failure<String>]
      #   Success with application or Failure if no application found
      def fetch_related_application(enrollment)
        application = find_application_via_tax_household(enrollment)

        if application.blank?
          application = enrollment.family.latest_determined_application_for_year(enrollment.effective_on.year)
          application.present? ? Success(application) : Failure('Missing application')
        else
          Success(application)
        end
      end

      # Attempts to find application through tax household enrollment relationship
      # @param enrollment [HbxEnrollment] The enrollment to search from
      #
      # @return [FinancialAssistance::Application, nil] Application if found, nil otherwise
      def find_application_via_tax_household(enrollment)
        tax_household_enrollment = TaxHouseholdEnrollment.find_by(enrollment_id: enrollment.id)
        return nil unless tax_household_enrollment

        application_gid = tax_household_enrollment.tax_household&.tax_household_group&.application_gid
        GlobalID::Locator.locate(application_gid) if application_gid
      end

      # Updates eligibilities for all applicants in the application
      #
      # Determines enrollment context (new vs renewal) and processes each applicant
      # to update their APTC/CSR and individual market eligibilities based on
      # their enrollment status and benefit usage.
      def update_applicants(application, enrollment)
        is_new_enrollment = is_a_new_enrollment?(enrollment)
        enrollment_context = enrollment_context(enrollment)
        application.applicants.each do |applicant|
          update_applicant_eligibilities(applicant, is_new_enrollment, enrollment_context)
        end

        save_application(application)
      rescue StandardError => e
        Failure("Failed to update applicants: #{e.message}")
      end

      # Saves the application with comprehensive error handling
      #
      # Attempts to persist all evidence updates made to the application,
      # providing detailed error information if the save fails.
      def save_application(application)
        application.save!
        Success(application)
      rescue StandardError => e
        Failure("Failed to save application: #{e.message}")
      end

      # Updates eligibilities for a single applicant based on enrollment context
      #
      # Conditionally updates APTC/CSR eligibility (only for new QHP enrollments)
      # and always updates individual market eligibility based on enrollment status.
      #
      # @param applicant [FinancialAssistance::Applicant] The applicant to update
      # @param is_new_enrollment [Boolean] Whether this is a new enrollment vs renewal
      # @param enrollment_context [Hash] Context information about the enrollment
      # @option enrollment_context [Array<HbxEnrollment>] :active_enrollments Currently active enrollments
      # @option enrollment_context [String] :enrollment_hbx_id HBX ID of the enrollment
      # @option enrollment_context [Boolean] :is_qhp Whether this is a Health enrollment
      def update_applicant_eligibilities(applicant, is_new_enrollment, enrollment_context)
        applicant_context = applicant_context(applicant, enrollment_context)
        update_aptc_csr_eligibility(applicant, applicant_context) if is_new_enrollment && enrollment_context[:is_qhp]
        update_individual_market_eligibility(applicant, applicant_context)
      end

      # Updates individual market eligibility evidence states
      #
      # Updates evidence states based on whether the applicant is enrolled,
      # then triggers a redetermination of the eligibility state.
      #
      # @param applicant [FinancialAssistance::Applicant] The applicant to update
      # @param applicant_context [Hash] Context about the applicant's enrollment status
      # @option applicant_context [Boolean] :is_enrolled Whether applicant is enrolled
      # @option applicant_context [String] :enrollment_hbx_id The enrollment HBX ID
      #
      # @return [void]
      #
      # @example Enrolled applicant
      #   update_individual_market_eligibility(enrolled_applicant, enrolled_context)
      #   # Calls update_evidences_for_enrollment_change
      #
      # @example Non-enrolled applicant
      #   update_individual_market_eligibility(non_enrolled_applicant, non_enrolled_context)
      #   # Calls update_outstanding_evidences_for_non_enrolled
      def update_individual_market_eligibility(applicant, applicant_context)
        individual_market_eligibility = applicant.individual_market_eligibility
        return unless individual_market_eligibility.present?

        update_evidences(individual_market_eligibility, applicant_context[:is_enrolled])
        update_eligibility(individual_market_eligibility, applicant_context[:enrollment_hbx_id])
      end

      def update_eligibility(eligibility, enrollment_hbx_id)
        reason = "Redetermined due to enrollment #{enrollment_hbx_id} change"
        eligibility.determine_eligibility_state(reason)
      end

      # Updates APTC/CSR eligibility evidence states
      #
      # Updates evidence states based on whether the applicant has APTC or CSR benefits,
      # then triggers a redetermination. Only processes enrolled applicants.
      #
      # @param applicant [FinancialAssistance::Applicant] The applicant to update
      # @param applicant_context [Hash] Context about the applicant's benefit usage
      # @option applicant_context [Boolean] :is_enrolled Whether applicant is enrolled
      # @option applicant_context [Boolean] :has_aptc_csr Whether applicant uses APTC/CSR
      # @option applicant_context [String] :enrollment_hbx_id The enrollment HBX ID
      #
      # @return [void]
      #
      # @example Applicant with APTC/CSR
      #   update_aptc_csr_eligibility(aptc_applicant, aptc_context)
      #   # Updates evidences based on APTC/CSR usage
      #
      # @example Non-enrolled applicant
      #   update_aptc_csr_eligibility(non_enrolled_applicant, context)
      #   # Returns early, no updates performed
      def update_aptc_csr_eligibility(applicant, applicant_context)
        aptc_csr_eligibility = applicant.aptc_csr_eligibility
        return unless aptc_csr_eligibility.present? && applicant_context[:is_enrolled]

        update_evidences(aptc_csr_eligibility, applicant_context[:has_aptc_csr])
        update_eligibility(aptc_csr_eligibility, applicant_context[:enrollment_hbx_id])
      end

      # Builds context information for an applicant's eligibility updates
      #
      # Determines whether the applicant is enrolled in active enrollments
      # and whether they have APTC or CSR benefits applied.
      #
      # @param applicant [FinancialAssistance::Applicant] The applicant to analyze
      # @param enrollment_context [Hash] The enrollment context information
      # @option enrollment_context [Array<HbxEnrollment>] :active_enrollments Active enrollments for the family
      # @option enrollment_context [String] :enrollment_hbx_id The enrollment HBX ID
      #
      # @return [Hash] Context hash with applicant-specific information
      # @option return [Boolean] :is_enrolled Whether applicant is enrolled
      # @option return [Boolean] :has_aptc_csr Whether applicant has APTC/CSR benefits
      # @option return [String] :enrollment_hbx_id The enrollment HBX ID
      #
      # @example Enrolled applicant with APTC
      #   applicant_context(aptc_applicant, enrollment_context)
      #   # => { is_enrolled: true, has_aptc_csr: true, enrollment_hbx_id: "12345" }
      #
      # @example Non-enrolled applicant
      #   applicant_context(non_enrolled_applicant, enrollment_context)
      #   # => { is_enrolled: false, has_aptc_csr: false, enrollment_hbx_id: "12345" }
      def applicant_context(applicant, enrollment_context)
        is_enrolled = enrollment_context[:active_enrollments].map(&:hbx_enrollment_members).flatten.any? { |member| member.applicant_id == applicant.family_member_id }
        has_aptc_csr = is_enrolled ? has_aptc_csr_enrollment?(applicant, enrollment_context[:active_enrollments]) : false

        {
          is_enrolled: is_enrolled,
          has_aptc_csr: has_aptc_csr,
          enrollment_hbx_id: enrollment_context[:enrollment_hbx_id]
        }
      end

      # Builds enrollment context information for evidence updates
      #
      # Gathers all active health enrollments for the same year and determines
      # enrollment characteristics needed for evidence processing.
      #
      # @param enrollment [HbxEnrollment] The enrollment that triggered the update
      #
      # @return [Hash] Context hash with enrollment information
      # @option return [Array<HbxEnrollment>] :active_enrollments Active health enrollments for the year
      # @option return [String] :enrollment_hbx_id The enrollment HBX ID
      # @option return [Boolean] :is_qhp Whether this is a qualified health plan enrollment
      #
      # @example QHP enrollment context
      #   enrollment_context(qhp_enrollment)
      #   # => { active_enrollments: [...], enrollment_hbx_id: "12345", is_qhp: true }
      #
      # @example Dental enrollment context
      #   enrollment_context(dental_enrollment)
      #   # => { active_enrollments: [...], enrollment_hbx_id: "12345", is_qhp: false }
      def enrollment_context(enrollment)
        active_enrollments = fetch_active_enrollments(enrollment)

        {
          active_enrollments: active_enrollments,
          enrollment_hbx_id: enrollment.hbx_id,
          is_qhp: enrollment.health?
        }
      end

      # Fetches all active health enrollments for the same year as the given enrollment
      #
      # Retrieves enrolled and renewing health enrollments from the same family
      # for the same coverage year, which are needed to determine overall
      # enrollment context for evidence updates.
      #
      # @param enrollment [HbxEnrollment] The reference enrollment
      #
      # @return [ActiveRecord::Relation<HbxEnrollment>] Active health enrollments
      #
      # @example
      #   fetch_active_enrollments(enrollment)
      #   # => [#<HbxEnrollment>, #<HbxEnrollment>, ...]
      def fetch_active_enrollments(enrollment)
        enrollment.family
                  .hbx_enrollments
                  .enrolled_and_renewing
                  .by_health
                  .by_year(enrollment.effective_on.year)
      end

      # Determines if the enrollment represents a new enrollment vs a renewal
      def is_a_new_enrollment?(enrollment)
        transition = enrollment.workflow_state_transitions
                               .only(:to_state, :from_state)
                               .desc(:created_at)
                               .first

        raise 'Missing workflow state transition' unless transition
        to_state = transition.to_state
        from_state = transition.from_state

        return false if to_state == 'coverage_selected' && ['renewing_coverage_selected', 'auto_renewing'].include?(from_state)

        true
      end

      def has_aptc_csr_enrollment?(applicant, active_enrollments)
        active_enrollments.any? do |active_enrollment|
          active_enrollment.has_aptc_or_csr_applied? if active_enrollment.hbx_enrollment_members.where(applicant_id: applicant.family_member_id).first.present?
        end
      end

      # Updates evidence states based on enrollment and benefit usage
      def update_evidences(eligibility, enrolled_and_or_aptc_csr_used)
        if enrolled_and_or_aptc_csr_used
          eligibility.update_evidences_for_enrollment_change
        else
          eligibility.update_outstanding_evidences_for_non_enrolled
        end
      end

      # Recreates family eligibility determination after evidence updates
      def recreate_family_eligibility_determination(enrollment)
        family = enrollment.family
        ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
      end
    end
  end
end