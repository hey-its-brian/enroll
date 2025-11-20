module RuleSet
  module HbxEnrollment
    class IndividualMarketVerification
      attr_reader :hbx_enrollment

      def initialize(h_enrollment)
        @hbx_enrollment = h_enrollment
      end

      def applicable?
        !hbx_enrollment.product_id.nil? &&
          hbx_enrollment.affected_by_verifications_made_today? && (!hbx_enrollment.benefit_sponsored?)
      end

      def roles_for_determination
        hbx_enrollment.hbx_enrollment_members.map(&:person).map(&:consumer_role).compact
      end

      def determine_next_state
        return true, :move_to_enrolled! if (any_outstanding? || verification_ended?) && hbx_enrollment.may_move_to_enrolled?
        member_outstanding = any_outstanding? || verification_ended?
        if any_pending?
          return member_outstanding, :move_to_pending! if hbx_enrollment.may_move_to_pending?
        else
          return member_outstanding, :move_to_enrolled! if hbx_enrollment.may_move_to_enrolled?
        end
        [member_outstanding, :do_nothing]
      end

      def any_outstanding?
        return false unless active_subjects.any?

        active_subjects.any? { |subject| subject.outstanding_verification_status.to_s == 'outstanding' }
      end

      def verification_ended?
        roles_for_determination.any?(&:verification_period_ended?)
      end

      def any_pending?
        roles_for_determination.any?(&:ssa_pending?) || roles_for_determination.any?(&:dhs_pending?) || roles_for_determination.any?(&:sci_verified?)
      end

      def active_subjects
        @active_subjects ||= begin
          eligibility = hbx_enrollment.family&.eligibility_determination

          if eligibility.present?
            enrollment_member_ids = hbx_enrollment.hbx_enrollment_members.map(&:applicant_id)
            active_family_member_ids = hbx_enrollment.family.family_members.active.pluck(:id)
            active_enrollment_member_ids = enrollment_member_ids & active_family_member_ids

            eligibility.subjects.select do |subject|
              family_member_id = extract_family_member_id_from_gid(subject.gid)
              active_enrollment_member_ids.include?(family_member_id)
            end
          else
            []
          end
        end
      end

      def extract_family_member_id_from_gid(gid)
        id_string = gid.to_s.split('/').last
        BSON::ObjectId.from_string(id_string)
      end
    end
  end
end
