# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Families
    class ApplyForFinancialAssistance
      include Dry::Monads[:do, :result]

      def call(family_id:)
        family = yield find_family(family_id)
        execute(family: family)
      end

      private

      def find_family(family_id)
        family = Family.find(family_id)
        Success(family)
      rescue
        Failure('Cannot find family')
      end

      def execute(family:)
        Success(family.active_family_members.collect {|family_member| family_member_attributes(family_member).deep_symbolize_keys})
      end

      def family_member_attributes(family_member)
        person_attributes(family_member.person, family_member.family).merge(family_member_id: family_member.id,
                                                                            is_primary_applicant: family_member.is_primary_applicant,
                                                                            is_consent_applicant: family_member.is_consent_applicant)
      end

      def person_attributes(person, family)
        attrs = person.attributes.slice(:first_name,
                                        :last_name,
                                        :middle_name,
                                        :name_pfx,
                                        :name_sfx,
                                        :gender,
                                        :ethnicity,
                                        :tribal_id,
                                        :tribal_state,
                                        :tribal_name,
                                        :tribe_codes,
                                        :no_ssn,
                                        :is_tobacco_user).symbolize_keys

        consumer_role = person.consumer_role
        attrs = attrs.merge({person_hbx_id: person.hbx_id,
                             ssn: person.ssn,
                             dob: person.dob.strftime("%d/%m/%Y"),
                             is_applying_coverage: consumer_role.is_applying_coverage,
                             five_year_bar_applies: consumer_role.five_year_bar_applies,
                             five_year_bar_met: consumer_role.five_year_bar_met,
                             qualified_non_citizen: construct_qualified_non_citizen(consumer_role),
                             citizen_status: person.citizen_status,
                             contact_method: consumer_role.contact_method,
                             relationship: get_relationship_kind(family, person),
                             is_consumer_role: true,
                             same_with_primary: false,
                             indian_tribe_member: consumer_role.is_tribe_member?,
                             is_incarcerated: person.is_incarcerated,
                             addresses: construct_association_fields(person.addresses),
                             phones: construct_association_fields(person.phones),
                             emails: construct_association_fields(person.emails)})

        attrs.merge(vlp_document_params(consumer_role))
      end

      def construct_qualified_non_citizen(consumer_role)
        qnc_code = consumer_role.lawful_presence_determination&.qualified_non_citizenship_result
        case qnc_code
        when 'Y'
          true
        when 'N'
          false
        else
          consumer_role.person.eligible_immigration_status
        end
      end

      def vlp_document_params(consumer_role)
        vlp_object = consumer_role.active_vlp_document
        return {} unless vlp_object
        vlp_attrs = vlp_object.attributes.symbolize_keys.slice(:alien_number,
                                                               :i94_number,
                                                               :visa_number,
                                                               :passport_number,
                                                               :sevis_id,
                                                               :naturalization_number,
                                                               :receipt_number,
                                                               :citizenship_number,
                                                               :card_number,
                                                               :country_of_citizenship,
                                                               :expiration_date,
                                                               :issuing_country)
        vlp_attrs.merge!({expiration_date: vlp_attrs[:expiration_date].strftime("%d/%m/%Y")}) if vlp_attrs[:expiration_date].present?
        vlp_attrs.merge!({vlp_subject: vlp_object[:subject], vlp_description: vlp_object[:description]})
        vlp_attrs
      end

      def get_relationship_kind(family, person)
        family.primary_person.find_relationship_with(person)
      end

      def construct_association_fields(records)
        records.collect{|record| record.attributes.except(:_id, :created_at, :updated_at, :tracking_version, :location_state_code, :full_text) }
      end
    end
  end
end
