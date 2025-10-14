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

    def qhp_application(*traits, new: false) # rubocop:disable Metrics/CyclomaticComplexity
      attributes = traits.extract_options!
      attributes.merge!(family_id: qhp_consumer.primary_family.id)
      return @qhp_application if @qhp_application.present? && !new
      @qhp_application = FactoryBot.create(:individual_market_application, *traits, attributes).tap do |application|
        application.update_attributes!(effective_on: TimeKeeper.date_of_record) if application.effective_on.blank?
        qhp_consumer.person.phones << FactoryBot.build(:phone, kind: "mobile")
        generate_dependent
        qhp_consumer.primary_family.family_members.each do |member|
          member&.person&.consumer_role&.active_vlp_document&.destroy
          traits = []
          traits += [:with_home_address, :with_mailing_address, :with_phone_number, :with_email] if member.is_primary_applicant?
          applicant = FactoryBot.create(:individual_market_applicant,
                                        *traits,
                                        application: application,
                                        family_member_id: member.id,
                                        person_name: {
                                          given_name: member.first_name,
                                          family_name: member.last_name
                                        },
                                        demographics: {
                                          dob: member.dob,
                                          gender: member.gender,
                                          no_ssn: '0',
                                          encrypted_ssn: member.ssn ? SymmetricEncryption.encrypt(member.ssn) : nil,
                                          is_incarcerated: '0',
                                          us_citizen: '1',
                                          naturalized_citizen: '0',
                                          citizen_status: 'us_citizen',
                                          indian_tribe_member: '0'
                                        },
                                        is_homeless: '0',
                                        is_primary_applicant: member.is_primary_applicant?,
                                        is_applying_coverage: '1',
                                        address_same_as_primary: !member.is_primary_applicant?)

          next if member.is_primary_applicant?
          rel = { source_id: applicant.id, relative_id: application.primary_applicant.id, kind: 'spouse' }
          application.relationships.create!(rel)
        end

        application.reload
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
