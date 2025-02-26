# frozen_string_literal: true

module BenefitSponsors
  module Services
    # Service to hire/fire assister
    class AssisterManagementService

      def assign_agencies(form)
        assign_agencies_for_employer(form)
      end

      def terminate_agencies(form)
        terminate_agencies_for_employer(form)
      end

      private

      def terminate_agencies_for_employer(form)
        @employer_profile = BenefitSponsors::Organizations::Profile.find(form.employer_profile_id)
        if form.termination_date
          @employer_profile.fire_assister_agency(form.termination_date)
          # @employer_profile.fire_general_agency!(form.termination_date)
          @employer_profile.save!
          true
        else
          false
        end
      end

      def assign_agencies_for_employer(form)
        @employer_profile = BenefitSponsors::Organizations::Profile.find(form.employer_profile_id)
        assign_assister_agency_for_emp(form.assister_agency_profile_id, form.assister_role_id)
        send_notices_associated_to_employer_profile(form.assister_agency_profile_id)
      end

      def send_notification(assister_role_id)
        invitation = BenefitSponsors::Services::InvitationEmailService.new({assister_role_id: assister_role_id, employer_profile: @employer_profile})
        invitation.send_assister_successfully_associated_email
      rescue StandardError => e
        puts e.inspect
        puts e.backtrace
      end

      def send_notices_associated_to_employer_profile(assister_agency_profile_id)
        invitation = BenefitSponsors::Services::InvitationEmailService.new({assister_agency_profile_id: assister_agency_profile_id, employer_profile: @employer_profile})
        invitation.send_general_agency_successfully_associated_email
      rescue StandardError => e
        Rails.logger.error do
          "#{e.inspect} #{e.backtrace}"
        end
      end

      def get_bson_id(id)
        BSON::ObjectId.from_string(id)
      end

      def assign_assister_agency_for_emp(assister_agency_profile_id, assister_role_id)
        assister_agency_profile = BenefitSponsors::Organizations::AssisterAgencyProfile.find(get_bson_id(assister_agency_profile_id))
        @employer_profile.assister_role_id = assister_role_id
        @employer_profile.hire_assister_agency(assister_agency_profile)
        @employer_profile.save!
        send_notification(assister_role_id)
      end

    end
  end
end
