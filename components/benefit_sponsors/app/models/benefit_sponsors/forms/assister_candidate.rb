# frozen_string_literal: true

module BenefitSponsors
  module Forms
    # Form for assisterCandidate as part of formservice pattern
    class AssisterCandidate < ::Forms::PersonSignup
      include ActiveModel::Validations
      include Validations::Email

      include ::Forms::PeopleNames
      include BenefitSponsors::Forms::NpnField

      attr_accessor :assister_agency_id, :assister_applicant_type, :market_kind, :languages_spoken, :working_hours, :accept_new_clients, :addresses

      validate :validate_assister_agency
      validate :validate_duplicate_aoid, :if => proc {|p| p.assister_applicant_type != 'staff'}

      # will we want these same validations on the assister_org_id?
      validates :assister_org_id,
                length: { maximum: 10, message: "%{value} is not a valid Assister Organization ID" },
                format: { with: /\A[1-9][0-9]+\z/, message: "%{value} is not a valid Assister Organization ID" },
                numericality: true,
                :if => proc {|p| p.assister_applicant_type != 'staff'}

      validates :email, :email => true, :allow_blank => false

      validates :email, :email => true, :allow_blank => false, format: {
        with: /\A[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\z/,
        message: "%{value} is not a valid email"
      }

      def initialize(*attributes)
        @addresses = []
        ensure_addresses
        super
      end

      def save
        return false unless valid?

        begin
          match_or_create_person
          person.save!
        rescue TooManyMatchingPeople
          errors.add(:base, "Too many people match the criteria provided for your identity. Please contact HBX-Customer Service.")
          return false
        end

        assister_agency_profile = Organizations::AssisterAgencyProfile.find(self.assister_agency_id)
        if assister_role?
          person.assister_role = ::AssisterRole.new({
                                                      :provider_kind => 'assister',
                                                      :assister_org_id => self.assister_org_id,
                                                      :assister_agency_profile => assister_agency_profile,
                                                      :market_kind => market_kind,
                                                      :languages_spoken => languages_spoken,
                                                      :working_hours => working_hours,
                                                      :accept_new_clients => accept_new_clients
                                                    })
        else
          person.assister_agency_staff_roles << ::AssisterAgencyStaffRole.new(:assister_agency_profile => assister_agency_profile)
        end

        true
      end

      def match_or_create_person
        super
        person.addresses << @addresses.select(&:valid?)
      end

      def validate_assister_agency
        if self.assister_agency_id.blank?
          errors.add(:base, "Please select your assister agency.")
        elsif BenefitSponsors::Organizations::AssisterAgencyProfile.find(self.assister_agency_id).blank?
          errors.add(:base, "Unable to locate the assister agnecy. Please contact HBX.")
        end
      end

      def validate_duplicate_aoid
        errors.add(:base, "Assister Organization ID has already been claimed by another assister. Please contact HBX.") if Person.where("assister_role.assister_org_id" => assister_org_id).any?
      end

      def assister_role?
        self.assister_applicant_type != 'staff'
      end

      def ensure_addresses
        @addresses = [Address.new(kind: 'home')] if @addresses.empty?
      end

      def addresses_attributes
        @addresses.map(&:attributes)
      end

      def addresses_attributes=(attrs)
        @addresses = attrs.map { |_, att_set| Address.new(att_set) }
      end
    end
  end
end
