# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Notices
    # IVL open enrollment reverification notice
    class IvlOeReverificationTrigger
      include Dry::Monads[:do, :result]
      include EventSource::Command
      include EventSource::Logging

      # @param [Family] family object (required)
      # @return [Dry::Monads::Result]

      def call(params)
        values = yield validate(params)
        event_name = yield determine_event_name(values)
        payload = yield build_family_payload(values[:family])
        event = yield build_event(payload, event_name)
        result = yield publish_response(event)

        Success(result)
      end

      private

      # { family: family, notice_type: 'oeq' }
      # { family: family, notice_type: 'oeg' }
      def validate(params)
        return Failure('notice_type is invalid. It should be either oeg or oeq') if %w[oeg oeq].exclude?(params[:notice_type])
        return Failure('family is required for oeq or oeg notices') unless params[:family].is_a?(Family)

        Success(params)
      end

      def determine_event_name(values)
        case values[:notice_type]
        when 'oeq'
          Success('qhp_eligible_on_reverification')
        when 'oeg'
          Success('expired_consent_during_reverification')
        end
      end

      def build_addresses(person)
        address = person.mailing_address
        [
          {
            :kind => address.kind,
            :address_1 => address.address_1.presence,
            :address_2 => address.address_2.presence,
            :address_3 => address.address_3.presence,
            :state => address.state,
            :city => address.city,
            :zip => address.zip
          }
        ]
      end

      def update_and_build_verification_types(person)
        person.consumer_role.types_include_to_notices.collect do |verification_type|
          {
            type_name: verification_type.type_name,
            validation_status: verification_type.validation_status,
            due_date: verification_type.due_date
          }
        end
      end

      def build_family_member_hash(family)
        family.active_family_members.collect do |fm|
          person = fm.person
          outstanding_verification_types = person.consumer_role.types_include_to_notices
          member_hash = {
            is_primary_applicant: fm.is_primary_applicant,
            person: {
              hbx_id: person.hbx_id,
              person_name: { first_name: person.first_name, last_name: person.last_name },
              person_demographics: { gender: person.gender, dob: person.dob, is_incarcerated: person.is_incarcerated || false },
              person_health: { is_tobacco_user: person.is_tobacco_user },
              is_active: person.is_active,
              is_disabled: person.is_disabled,
              consumer_role: build_consumer_role(person.consumer_role),
              addresses: build_addresses(person)
            }
          }
          member_hash[:person].merge!(verification_types: update_and_build_verification_types(person)) if outstanding_verification_types.present?
          member_hash
        end
      end

      def build_consumer_role(consumer_role)
        {
          is_applying_coverage: consumer_role.is_applying_coverage,
          contact_method: consumer_role.contact_method,
          five_year_bar: consumer_role.five_year_bar,
          requested_coverage_start_date: consumer_role.requested_coverage_start_date,
          aasm_state: consumer_role.aasm_state,
          is_applicant: consumer_role.is_applicant,
          is_state_resident: consumer_role.is_state_resident,
          identity_validation: consumer_role.identity_validation,
          identity_update_reason: consumer_role.identity_update_reason,
          application_validation: consumer_role.application_validation,
          application_update_reason: consumer_role.application_update_reason,
          identity_rejected: consumer_role.identity_rejected,
          application_rejected: consumer_role.application_rejected,
          lawful_presence_determination: {}
        }
      end

      def build_household_hash(family)
        family.households.collect do |household|
          {
            start_date: household.effective_starting_on,
            is_active: household.is_active,
            coverage_households: household.coverage_households.collect { |ch| {is_immediate_family: ch.is_immediate_family, coverage_household_members: ch.coverage_household_members.collect {|chm| {is_subscriber: chm.is_subscriber}}} }
          }
        end
      end

      def documents_needed?(family)
        family.active_family_members.any? { |member| member.person.consumer_role.types_include_to_notices.present? }
      end

      def build_family_payload(family)
        payload = { family_members: build_family_member_hash(family), households: build_household_hash(family), hbx_id: family.hbx_assigned_id.to_s, documents_needed: documents_needed?(family) }
        family_contract = AcaEntities::Contracts::Families::FamilyContract.new.call(payload)
        return Failure("invalid payload for family id: #{family.id}") unless family_contract.success?

        family_entity = AcaEntities::Families::Family.new(family_contract.to_h)

        Success(family_entity)
      end

      def build_event(payload, event_name)
        result = event("events.individual.notices.#{event_name}", attributes: payload.to_h)
        unless Rails.env.test?
          logger.info('-' * 100)
          logger.info(
            "Enroll Reponse Publisher to external systems(polypress),
            event_key: events.individual.notices.#{event_name}, attributes: #{payload.to_h}, result: #{result}"
          )
          logger.info('-' * 100)
        end
        result
      end

      def publish_response(event)
        event.publish

        Success("Event published successfully: #{event.name}")
      end
    end
  end
end
