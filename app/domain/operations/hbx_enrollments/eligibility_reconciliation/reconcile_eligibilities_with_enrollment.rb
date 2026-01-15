# frozen_string_literal: true

module Operations
  module HbxEnrollments
    module EligibilityReconciliation
      # Synchronizes the eligibilities of the application coupled to the enrollment based on membership status.
      #
      # Re-evaluates eligibility relevance based on enrollment changes using the following rules:
      # - APTC/CSR eligibility relevance is driven by membership with APTC/CSR applied
      # - Individual Market eligibility relevance is driven by membership alone
      # The eligibilities are then reconciled with the enrollment by escalating or downgrading evidences
      # based on these relevance rules.
      #
      # @param params [Hash] Parameters containing enrollment object
      # @option params [HbxEnrollment] :enrollment The enrollment to reconcile eligibilities for
      #
      # @return [Dry::Monads::Success<FinancialAssistance::Application>, Dry::Monads::Failure<String>]
      #   Success with updated application or Failure with error message
      #
      # @see HbxEnrollment#generate_enrollment_saved_event
      # @see Subscribers::EnrollmentSubscriber
      # @see EligibilityReconciliation::Applicants::ReconcileApplicant
      class ReconcileEligibilitiesWithEnrollment
        include Dry::Monads[:do, :result]

        def call(params)
          yield validate(params)
          application = yield fetch_related_application
          reconcile_application(application)
        end

        private

        # Validates input parameters
        #
        # @param params [Hash] Input parameters containing enrollment object
        # @option params [HbxEnrollment] :enrollment The enrollment to reconcile
        #
        # @return [Dry::Monads::Success<HbxEnrollment>, Dry::Monads::Failure<String>]
        #   Success with enrollment or Failure with error message
        def validate(params)
          return Failure('Missing enrollment') unless params[:enrollment].present?

          @enrollment = params[:enrollment]
          return Failure('Invalid enrollment object') unless @enrollment.is_a?(HbxEnrollment)

          Success(@enrollment)
        end

        # Fetches the application related to the enrollment
        #
        # Uses the enrollment's built-in method to find the related application
        # through either tax household enrollment relationship or latest determined application.
        #
        # @return [Dry::Monads::Success<FinancialAssistance::Application>, Dry::Monads::Failure<String>]
        #   Success with application or Failure if no application found
        def fetch_related_application
          application = @enrollment.related_application
          application.present? ? Success(application) : Failure('Missing application')
        end

        # Reconcilies the application with the enrollment by reconciling each applicant's eligibilities
        #
        # @param application [FinancialAssistance::Application] The application to reconcile
        # @return [Dry::Monads::Success<FinancialAssistance::Application>, Dry::Monads::Failure<String>]
        def reconcile_application(application)
          active_enrollments = fetch_active_enrollments

          application.applicants.each do |applicant_model|
            result = Operations::HbxEnrollments::EligibilityReconciliation::Applicants::ReconcileApplicant.new.call({
                                                                                                                      applicant: applicant_model,
                                                                                                                      enrollment: @enrollment,
                                                                                                                      active_enrollments: active_enrollments
                                                                                                                    })

            return result if result.failure?
          end

          save_application(application)
        rescue StandardError => e
          Failure("Failed to update applicants: #{e.message}")
        end

        # Fetches all active health enrollments for the same year as the enrollment
        def fetch_active_enrollments
          @enrollment.family
                     .hbx_enrollments
                     .enrolled_and_renewing
                     .by_year(@enrollment.effective_on.year)
        end

        # Saves the application with comprehensive error handling
        #
        # Attempts to persist all evidence updates made to the application,
        # providing the application object if successful.
        def save_application(application)
          application.save!
          Success(application)
        rescue StandardError => e
          Failure("Failed to save application: #{e.message}")
        end
      end
    end
  end
end
