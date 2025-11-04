# frozen_string_literal: true

module IndividualMarket
  # Cucumber helper methods to be used with the QHP application flow
  module IndividualMarketWorld
    def qhp_consumer(*traits)
      attributes = traits.extract_options!
      @qhp_consumer ||= FactoryBot.create(:user, :consumer, :with_consumer_role_and_ssn, *traits, attributes)
    end

    def create_mock_family_eligibility_determination
      family = qhp_consumer.person.primary_family
      determination = Eligibilities::Determination.new({
                                                         effective_date: Date.today,
                                                         outstanding_verification_status: 'verified',
                                                         outstanding_verification_earliest_due_date: nil,
                                                         outstanding_verification_document_status: 'verified'
                                                       })

      family.eligibility_determination = determination
      family.save!
    end

    def qhp_application(*traits, new: false)
      return @qhp_application if @qhp_application.present? && !new

      attributes = prepare_application_attributes(traits)
      @qhp_application = create_and_setup_application(traits, attributes)
    end

    def prepare_application_attributes(traits)
      attributes = traits.extract_options!
      attributes.merge!(family_id: qhp_consumer.primary_family.id)

      current_date = TimeKeeper.date_of_record
      add_attributes_for_application_year(traits, attributes, current_date.year)
    end

    def create_and_setup_application(traits, attributes)
      FactoryBot.create(:individual_market_application, *traits, attributes).tap do |application|
        setup_application_details(application)
        setup_family_members_and_applicants(application)
        application.reload
      end
    end

    def setup_application_details(application)
      current_date = TimeKeeper.date_of_record
      effective_date = set_application_effective_date(application.assistance_year, current_date)
      application.update_attributes!(effective_on: effective_date) if application.effective_on.blank?

      add_phone_to_consumer
      generate_dependent
    end

    def add_phone_to_consumer
      qhp_consumer.person.phones << FactoryBot.build(:phone, kind: "mobile")
    end

    def setup_family_members_and_applicants(application)
      qhp_consumer.primary_family.family_members.each do |member|
        cleanup_member_documents(member)
        applicant = create_applicant_for_member(application, member)
        create_relationship_for_dependent(application, applicant) unless member.is_primary_applicant?
      end
    end

    def cleanup_member_documents(member)
      member&.person&.consumer_role&.active_vlp_document&.destroy
    end

    def create_applicant_for_member(application, member)
      traits = determine_applicant_traits(member)

      FactoryBot.create(:individual_market_applicant,
                        *traits,
                        application: application,
                        family_member_id: member.id,
                        person_name: build_person_name(member),
                        demographics: build_demographics(member),
                        is_homeless: '0',
                        is_primary_applicant: member.is_primary_applicant?,
                        is_applying_coverage: '1',
                        address_same_as_primary: !member.is_primary_applicant?)
    end

    def determine_applicant_traits(member)
      traits = []
      traits += [:with_home_address, :with_mailing_address, :with_phone_number, :with_email] if member.is_primary_applicant?
      traits
    end

    def build_person_name(member)
      {
        given_name: member.first_name,
        family_name: member.last_name
      }
    end

    def build_demographics(member)
      {
        dob: member.dob,
        gender: member.gender,
        no_ssn: '0',
        encrypted_ssn: member.ssn ? SymmetricEncryption.encrypt(member.ssn) : nil,
        is_incarcerated: '0',
        us_citizen: '1',
        naturalized_citizen: '0',
        citizen_status: 'us_citizen',
        indian_tribe_member: '0'
      }
    end

    def create_relationship_for_dependent(application, applicant)
      rel = {
        source_id: applicant.id,
        relative_id: application.primary_applicant.id,
        kind: 'spouse'
      }
      application.relationships.create!(rel)
    end

    def add_attributes_for_application_year(traits, attributes, current_year)
      if traits.include?(:prospective)
        # for prospective applications, use next year
        attributes.merge!(assistance_year: current_year + 1)
      else
        attributes.merge!(assistance_year: current_year)
      end
    end

    def set_application_effective_date(assistance_year, current_date)
      # if assistance year is next year, start jan 1st
      if assistance_year > current_date.year
        Date.new(assistance_year, 1, 1)
      else
        Date.today
      end
    end

    def generate_dependent(relationship_kind = 'spouse')
      FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, :with_ssn).tap do |dependent|
        qhp_consumer.primary_family.family_members.create(person: dependent)
        qhp_consumer.person.ensure_relationship_with(dependent, relationship_kind)
      end
    end

    def determine_eligible_or_ineligible_applicants(role, application)
      applicants = []
      applicants << application.primary_applicant if ['primary', 'both'].include?(role)
      applicants << application.non_primary_applicants.first if ['dependent', 'both'].include?(role)
      applicants
    end
  end
end

World(IndividualMarket::IndividualMarketWorld)
