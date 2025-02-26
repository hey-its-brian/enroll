# frozen_string_literal: true

module BenefitSponsors
  module Services
    # service to update assister agency
    class UpdateAssisterAgencyService

      attr_accessor :assister_agency, :legal_name

      def initialize(options = {})
        @legal_name = options[:legal_name]
        @assister_agency = find_assister_agency(@legal_name) unless @legal_name.blank?
      end

      def update_assister_profile_id(attr = {})
        return if attr.empty? || attr[:hbx_id].nil? || assister_agency.nil?

        person = find_person(attr[:hbx_id])
        assister_staff_roles = person.assister_agency_staff_roles

        return "person not present" unless person.present?
        return 2  if assister_staff_roles.count >= 2
        return "Already Exist" if assister_staff_roles.detect { |staff_role| staff_role.benefit_sponsors_assister_agency_profile_id.to_s == assister_agency.id.to_s }

        person.assister_agency_staff_roles.first.update_attributes!(benefit_sponsors_assister_agency_profile_id: assister_agency.id)
      end

      def update_assister_assignment_date(attr = {})
        return if attr.empty?
        hbx_ids = attr[:hbx_ids]
        new_date = attr[:start_date]
        hbx_ids.each do |hbx_id|
          organization = find_organization(hbx_id)
          next unless organization.present?
          organization.employer_profile.active_assister_agency_account.update_attributes(start_on: new_date)
        end
      end

      def update_assister_agency_attributes(attr = {})
        return if attr.empty?
        assister_agency.update_attributes!(attr)
      end

      def update_organization_attributes(attr = {})
        return if attr.empty?
        assister_agency.organization.update_attributes!(attr)
      end

      def assign_assister_agency_to_employer(employer_profile_id, start_on = TimeKeeper.date_of_record)
        return if employer_profile_id.nil?
        employer_profile = find_profile(employer_profile_id)

        return unless employer_profile.present?
        # so stupid this line should go away
        employer_profile.assister_role_id = assister_agency.primary_assister_role
        employer_profile.hire_assister_agency(assister_agency, start_on)
        employer_profile.save!
        send_notification(assister_role, employer_profile)
      end

      def remove_assister_agency_to_employer(employer_profile_id, terminate_on = TimeKeeper.date_of_record)
        return if employer_profile_id.nil?
        employer_profile = find_profile(employer_profile_id)

        return unless employer_profile.present?
        employer_profile.fire_assister_agency(terminate_on)
        employer_profile.save!
      end

      def send_notification(assister_role)
        invitation = BenefitSponsors::Services::InvitationEmails.new({assister_role_id: assister_role.id, employer_profile: employer_profile})
        invitation.send_assister_successfully_associated_email
      rescue StandardError => e
        puts e.inspect
        puts e.backtrace
      end

      private

      def find_assister_agency(legal_name)
        organization = BenefitSponsors::Organizations::Organization.assister_agency_profiles.where(legal_name: legal_name).first
        raise "organizational assister agency profile do not exist with fein #{legal_name}" unless organization
        organization.assister_agency_profile
      end

      def find_person(hbx_id)
        Person.by_hbx_id(hbx_id).first
      end

      def find_profile(employer_profile_id)
        BenefitSponsors::Organizations::Profile.find(employer_profile_id)
      end

      def find_organization(hbx_id)
        BenefitSponsors::Organizations::Organization.where(hbx_id: hbx_id).first
      end

    end
  end
end