# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module DataFixes
    # This class is to Trigger all ConsumerRole OnUpdate events.
    #   1. Determine Verifications(SSA/VLP)
    class TransitionConsumerRolesToFullyVerified
      include Dry::Monads[:do, :result]

      def call(params)
        @family_id = yield validate(params)
        family, members = yield fetch_active_family_members
        _result = yield process_members(members, family) { |member| process(member) }

        Success(@result_collection)
      end

      private

      def validate(params)
        return Failure("Family id is not present") unless params[:family_id]
        @logger = if params[:logger].present?
                    params[:logger]
                  else
                    Logger.new($stdout)
                  end

        @result_collection = []

        Success(params[:family_id])
      end

      def fetch_active_family_members
        family = Family.where(id: @family_id).first
        unless family
          @logger.error "#{@family_id}: No family found for family id: #{@family_id}"
          return Failure("No family found for the given family id: #{@family_id}")
        end

        Success([family, family.active_family_members])
      end

      def process_members(members, family)
        @logger.info "#{@family_id}: Processing family id: #{@family_id}"
        enrollments = family.hbx_enrollments.enrolled.by_year(2026)
        @unverified_enrollment_hbx_ids = enrollments.where(:aasm_state => 'unverified').flatten.map(&:hbx_id)

        if @unverified_enrollment_hbx_ids.blank?
          @logger.error "#{@family_id}: No unverified_enrollments found"
          csv_error_row(0, "No unverified_enrollments found for the given family")
          return Failure("No unverified_enrollments found for the given family: #{@family_id}")
        end

        primary_person = family.primary_person
        @primary_hbx_id = primary_person.hbx_id
        members.each do |family_member|
          yield(family_member) if block_given?
        end

        @unverified_enrollment_hbx_ids.each do |hbx_id|
          enrollment = HbxEnrollment.find_by(hbx_id: hbx_id)
          workflow_state_transition = enrollment.workflow_state_transitions.where(from_state: 'unverified', to_state: 'coverage_selected', :created_at.gte => Date.today).max_by(&:created_at)
          next unless workflow_state_transition
          workflow_state_transition.update_attributes(reason: "Transition to coverage selected after consumer role moved to fully verified via CRM 28606")
        end

        @logger.info "#{@family_id}: Successfully processed family id: #{@family_id}"
        Success(true)
      rescue StandardError => e
        @logger.error "#{@family_id}: Failed to process family id: #{@family_id} with error #{e.message}"
        csv_error_row(@unverified_enrollment_hbx_ids&.count, e.message)
        Failure("Failed to process family id: #{@family_id} with error #{e.message}")
      end

      def process(family_member)
        person = family_member.person
        consumer_role = person.consumer_role

        unless consumer_role.ssa_pending? || consumer_role.dhs_pending?
          @logger.error "#{@family_id}: Consumer role is not in pending state for person hbx_id: #{person.hbx_id}"
          csv_error_row(@unverified_enrollment_hbx_ids&.count, "Consumer role is not in pending state")
          return
        end

        consumer_role.update_attributes(aasm_state: "fully_verified")
        reason = "Transition to fully verified to update enrollment to coverage selected via CRM 28606"

        if consumer_role.ssa_pending?
          consumer_role.workflow_state_transitions.create(from_state: "ssa_pending", to_state: "fully_verified", event: "ssn_valid_citizenship_valid", reason: reason)
        elsif consumer_role.dhs_pending?
          consumer_role.workflow_state_transitions.create(from_state: "dhs_pending", to_state: "fully_verified", event: "pass_dhs", reason: reason)
        end

        consumer_role.notify_of_eligibility_change
        csv_row(person, consumer_role, "Triggered consumer role notify_of_eligibility_change")
      end

      def csv_error_row(unverified_enrollments_count, message)
        @result_collection << [@family_id,  'n/a', 'n/a', 'n/a', unverified_enrollments_count, message] if @result_collection
      end

      def csv_row(person, consumer_role, message)
        @result_collection << [@family_id,  @primary_hbx_id, person.hbx_id, consumer_role.aasm_state, @unverified_enrollment_hbx_ids&.count, message] if @result_collection
      end
    end
  end
end

