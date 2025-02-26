# frozen_string_literal: true

module BenefitSponsors
  module Accounts
    # This model is responsible for handling the logic and data related to the assister agency's account
    class AssisterAgencyAccount
      include Mongoid::Document
      include SetCurrentUser
      include Mongoid::Timestamps
      include ::BenefitSponsors::Concerns::Observable
      include ::BenefitSponsors::ModelEvents::AssisterAgencyAccount

      embedded_in :benefit_sponsorship,
                  class_name: "::BenefitSponsors::BenefitSponsorships::BenefitSponsorship"

      embedded_in :family

      # Begin date of relationship
      field :start_on, type: DateTime

      # End date of relationship
      field :end_on, type: DateTime
      field :updated_by, type: String

      # Assister agency representing ER
      field :benefit_sponsors_assister_agency_profile_id, type: BSON::ObjectId

      # Assister writing_agent credited for enrollment and transmitted on 834
      field :writing_agent_id, type: BSON::ObjectId
      field :is_active, type: Boolean, default: true

      validates_presence_of :start_on, :benefit_sponsors_assister_agency_profile_id, :is_active

      default_scope -> {where(:is_active => true)}

      before_create :notify_observers
      after_save    :notify_on_save

      add_observer ::BenefitSponsors::Observers::AssisterAgencyAccountObserver.new, [:assister_fired?, :assister_hired?]
      #add_observer ::BenefitSponsors::Observers::NoticeObserver.new, [:process_assister_agency_events]

      # belongs_to assister_agency_profile
      def assister_agency_profile=(new_assister_agency_profile)
        raise ArgumentError, "expected AssisterAgencyProfile" unless new_assister_agency_profile.is_a?(BenefitSponsors::Organizations::AssisterAgencyProfile)
        self.benefit_sponsors_assister_agency_profile_id = new_assister_agency_profile._id
        @assister_agency_profile = new_assister_agency_profile
      end

      def assister_agency_profile
        return @assister_agency_profile if defined? @assister_agency_profile
        @assister_agency_profile = BenefitSponsors::Organizations::AssisterAgencyProfile.find(self.benefit_sponsors_assister_agency_profile_id) unless self.benefit_sponsors_assister_agency_profile_id.blank?
      end

      def aa_name
        Rails.cache.fetch("assister-agency-name-#{self.benefit_sponsors_assister_agency_profile_id}", expires_in: 12.hour) do
          legal_name
        end
      end

      def legal_name
        assister_agency_profile.present? ? assister_agency_profile.legal_name : ""
      end

      #TODO: based on new organization and profile
      def writing_agent=(new_writing_agent)
        raise ArgumentError, "expected AssisterRole" unless new_writing_agent.is_a?(AssisterRole)
        self.writing_agent_id = new_writing_agent._id
        @writing_agent = new_writing_agent
      end

      def writing_agent
        return @writing_agent if defined? @writing_agent
        @writing_agent = AssisterRole.find(writing_agent_id)
      end
    end
  end
end
