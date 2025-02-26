# frozen_string_literal: true

module BenefitSponsors
  module Services
    # service to register assister
    class AssisterRegistrationService
      def self.call(params, user)
        params_validation = resolve_create_request_params_validator.call(params)
        return params_validation unless params_validation.success?
        creation_request = resolve_virtual_model.new(params_validation.output)
        process_request(creation_request, user)
      end

      # Take a Creation Request and build the underlying assister agency profile
      # and assister role items as needed.
      # @param creation_request [::BenefitSponsors::Requests::AssisterAgencyProfileCreateRequest]
      # @param user [User]
      # @return [::BenefitSponsors::Services::ServiceResponse, ::Dry::Validation::Result]
      def self.process_request(creation_request, user)
        domain_validation = resolve_create_request_domain_validator.call(user: user, request: creation_request)
        return domain_validation unless domain_validation.success?
        assister_agency_profile = find_or_create_profile_and_organization(creation_request)
        person = find_or_create_person_for_assister(creation_request, assister_agency_profile)
        ServiceResponse.new(person)
      end

      # Determines if a given user providing certain identity data
      # may claim a given assister identity.  Exposed to the domain
      # validation as a helper.
      def self.may_claim_assister_identity?(user, request)
        return false if user.person && user.person.assister_role.present?
        matched_people = get_matched_people(request.first_name, request.last_name, request.dob)
        return false if matched_people.count > 1
        assister_role_person = existing_assister_role_person(request.assister_org_id)
        if assister_role_person
          return false if assister_role_person.user_id && (assister_role_person.user_id != user.id)
          return false unless person_data_matches?(assister_role_person, request.first_name, request.last_name, request.dob)
        end
        true
      end

      private

      # The following methods provide an avenue for dependency injection.
      def resolve_create_request_params_validator
        BenefitSponsors::AssisterAgencyRegistration::CreateRequestWithAchValidators::PARAMS.new
      end

      def resolve_create_request_domain_validator
        ::BenefitSponsors::AssisterAgencyRegistration::CreateRequestValidators::DOMAIN.new
      end

      def resolve_virtual_model
        BenefitSponsors::Requests::AssisterAgencyProfileWithAchCreateRequest
      end

      class << self

        def ensure_correct_contact_email(creation_request, matched_person)
          work_email = matched_person.emails.detect do |email|
            email.kind == "work"
          end
          if work_email.present?
            work_email.update_attributes!({
                                            address: creation_request.email
                                          })
          else
            person.emails << ::Email.new({
                                           kind: "work",
                                           address: creation_request.email
                                         })
          end
        end

        def find_or_create_person_for_assister(creation_request, assister_agency_profile)
          existing_person = existing_assister_role_person(creation_request.assister_org_id)
          if existing_person
            ensure_correct_contact_email(creation_request, existing_person)
            return existing_person
          end
          matched_people = get_matched_people(creation_request.first_name, creation_request.last_name, creation_request.dob)
          if matched_people.any?
            matched_person = matched_people.first
            ensure_correct_contact_email(creation_request, matched_person)
            add_assister_role_to_existing_person(matched_person, assister_agency_profile)
          else
            build_new_assister_role_and_person(creation_request, assister_agency_profile)
          end
        end

        def find_or_create_profile_and_organization(creation_request)
          office_locations = build_office_locations(creation_request)
          site = BenefitSponsors::ApplicationController.current_site
          ::BenefitSponsors::Organizations::AssisterAgencyProfile.create!({
                                                                            organization: ::BenefitSponsors::Organizations::ExemptOrganization.new({
                                                                                                                                                     legal_name: creation_request.legal_name,
                                                                                                                                                     dba: creation_request.dba,
                                                                                                                                                     site: site
                                                                                                                                                   }),
                                                                            market_kind: creation_request.practice_area,
                                                                            office_locations: office_locations,
                                                                            accepts_new_clients: creation_request.accepts_new_clients,
                                                                            working_hours: creation_request.evening_weekend_hours,
                                                                            languages_spoken: creation_request.languages
                                                                          })
        end

        def build_office_locations(creation_request)
          primary_office_location = build_office_location(creation_request, primary: true)
          other_office_locations = creation_request.office_locations.map do |ol|
            build_office_location(ol)
          end
          [primary_office_location] + other_office_locations
        end

        def build_office_location(office_location_parent, primary: false)
          BenefitSponsors::Locations::OfficeLocation.new({
                                                           is_primary: primary,
                                                           address: BenefitSponsors::Locations::Address.new({
                                                                                                              kind: (primary ? "primary" : office_location_parent.kind),
                                                                                                              address_1: office_location_parent.address.address_1,
                                                                                                              address_2: office_location_parent.address.address_2,
                                                                                                              city: office_location_parent.address.city,
                                                                                                              state: office_location_parent.address.state,
                                                                                                              zip: office_location_parent.address.zip
                                                                                                            }),
                                                           phone: BenefitSponsors::Locations::Phone.new({
                                                                                                          kind: "work",
                                                                                                          area_code: office_location_parent.phone.phone_area_code,
                                                                                                          number: office_location_parent.phone.phone_number,
                                                                                                          extension: office_location_parent.phone.phone_extension
                                                                                                        })
                                                         })
        end

        def add_assister_role_to_existing_person(_matched_person, assister_agency_profile)
          AssisterRole.create!(
            person: existing_person,
            assister_org_id: creation_request.assister_org_id,
            benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id
          )
        end

        def person_data_matches?(person, first_name, last_name, dob)
          (first_name.downcase == person.first_name.downcase) &&
            (last_name.downcase == person.last_name.downcase) &&
            (person.dob == dob)
        end

        def build_new_assister_role_and_person(creation_request, assister_agency_profile)
          person = Person.create({
                                   first_name: creation_request.first_name,
                                   last_name: creation_request.last_name,
                                   dob: creation_request.dob,
                                   emails: [::Email.new({
                                                          kind: "work",
                                                          address: creation_request.email
                                                        })],
                                   assister_role: AssisterRole.new({
                                                                     assister_org_id: creation_request.assister_org_id,
                                                                     benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id
                                                                   })
                                 })
          person.assister_role
        end

        def get_matched_people(first_name, last_name, dob)
          Person.where(
            first_name: regex_for(first_name),
            last_name: regex_for(last_name),
            dob: dob
          )
        end

        def existing_assister_role_person(assister_org_id)
          Person.by_assister_role_assister_org_id(assister_org_id).first
        end

        def regex_for(str)
          clean_string = ::Regexp.escape(str.strip)
          /^#{clean_string}$/i
        end
      end
    end
  end
end