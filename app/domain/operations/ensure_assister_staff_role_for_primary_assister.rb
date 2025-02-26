# frozen_string_literal: true

module Operations
  # Ensure that a primary assister has a assister staff role when the assister role
  # is 'activated'.
  #
  # There are multiple ways for assister roles to be 'activated':
  #
  # * acceptance of a assister role invitation when no other roles exist on that
  #   person
  # * approval of a assister role for a person who already has a consumer role
  # * successfully linking a person who already has a assister role via assister
  #   application approval
  #
  # Each of these have different rules for when and which roles we should
  # create, which states the staff role should transition through, and
  # if the agency needs some form of assister agency application manipulated.
  #
  # This class is designed to encapsulate all these different entry points and
  # present a common location for manipulation of these roles.  It is not
  # designed to solve the problem that we invoke this in multiple areas - only
  # to provide a single place for the logic until we can perform a more
  # comprehensive refactor of the behaviour.
  class EnsureAssisterStaffRoleForPrimaryAssister
    include Dry::Monads[:do, :result]

    VALID_SCENARIOS = [
      :application_approved,
      :consumer_role_linked,
      :invitation_claimed
    ].freeze

    def initialize(scenario)
      @scenario = scenario
      validate_scenario
    end

    def call(assister_role)
      case @scenario
      when :application_approved
        process_application_approved(assister_role)
      when :invitation_claimed
        process_invitation_claimed(assister_role)
      when :consumer_role_linked
        process_consumer_role_linked(assister_role)
      end
    end

    private

    def process_consumer_role_linked(assister_role)
      return if assister_role.blank?
      return unless assister_role.active?
      person = assister_role.person
      # Unless they are previously linked, and have a assister role, bail.
      return if person.consumer_role.blank?
      return if person.user.blank?
      # Otherwise, treat it like they 'claimed' an invitation.
      # At this point, they should have assister role in the correct status,
      # they merely needs us to check the staff roles.
      process_invitation_claimed(assister_role)
    end

    # Notice that we have introduced a duplicate check here.  Previously it
    # was possible to get 'double staff roles' via a combination of not
    # claiming the invitation and linking to a consumer role.
    def process_invitation_claimed(assister_role)
      person = assister_role.person
      assister_agency_profile = assister_role.assister_agency_profile
      existing_assister_staff_role = person.assister_agency_staff_roles.detect do |basr|
        basr.assister_agency_profile.id == assister_agency_profile.id
      end
      if existing_assister_staff_role
        existing_assister_staff_role.aasm_state = "active"
        existing_assister_staff_role.save!
      else
        person.assister_agency_staff_roles << ::AssisterAgencyStaffRole.new(
          {
            :assister_agency_profile => assister_agency_profile,
            :aasm_state => 'active'
          }
        )
      end
      person.save!
    end

    def process_application_approved(assister_role)
      return unless assister_role.is_primary_assister?

      basr = assister_role.create_basr_for_person_with_consumer_role
      agency = assister_role.assister_agency_profile
      agency.approve! if agency.may_approve?

      basr ||= assister_role.person.pending_basr_by_profile_id(assister_role.benefit_sponsors_assister_agency_profile_id)
      basr.assister_agency_accept! if basr&.may_assister_agency_accept?
    end

    def validate_scenario
      raise ArgumentError, "Scenario must be one of: #{VALID_SCENARIOS}" unless VALID_SCENARIOS.include?(@scenario)
    end
  end
end