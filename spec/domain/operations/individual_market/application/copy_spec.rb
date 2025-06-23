# frozen_string_literal: true

RSpec.describe Operations::IndividualMarket::Application::Copy, dbclean: :after_each do

  describe '#call' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:primary_applicant) { family.primary_applicant }
    let(:application_state) { :determined }
    let(:application) { FactoryBot.create(:individual_market_application, family: family, current_state: application_state) }
    let(:applicant) do
      FactoryBot.create(
        :individual_market_applicant,
        :with_person_name,
        :with_eligibilities,
        :with_work_address,
        :with_mailing_address,
        :with_home_address,
        :with_phone_number,
        :with_email,
        application: application,
        family_member_id: primary_applicant.id
      )
    end

    let(:demographics) do
      FactoryBot.create(
        :individual_market_demographics,
        applicant: applicant,
        citizen_status: 'alien_lawfully_present'
      )
    end
    let(:immigration_information) { FactoryBot.create(:individual_market_immigration_information, applicant: applicant) }
    let(:person_name) { applicant.person_name }
    let(:work_address) { applicant.addresses.work.first }
    let(:mailing_address) { applicant.addresses.mailing.first }
    let(:home_address) { applicant.addresses.home.first }
    let(:email) { applicant.emails.first }
    let(:phone) { applicant.phones.first }

    let(:origin) { :system }
    let(:generation_reason) { :manual }

    let(:result) do
      immigration_information
      demographics
      subject.call(
        application: applicant.application,
        origin: origin,
        generation_reason: generation_reason
      )
    end

    let(:result_application) { result.value! }
    let(:result_applicant) { result_application.applicants.first }
    let(:result_person_name) { result_applicant.person_name }
    let(:result_demographics) { result_applicant.demographics }
    let(:result_immigration_information) { result_applicant.immigration_information }
    let(:result_work_address) { result_applicant.addresses.work.first }
    let(:result_mailing_address) { result_applicant.addresses.mailing.first }
    let(:result_home_address) { result_applicant.addresses.home.first }
    let(:result_email) { result_applicant.emails.first }
    let(:result_phone) { result_applicant.phones.first }

    context 'with invalid params' do
      context 'when application is nil' do
        it 'returns failure with error message' do
          expect(
            subject.call(application: nil, origin: origin, generation_reason: generation_reason).failure
          ).to eq("Invalid application type: NilClass")
        end
      end

      context 'when application is not an IndividualMarket::Application' do
        it 'returns failure with error message' do
          expect(
            subject.call(application: 'Application', origin: origin, generation_reason: generation_reason).failure
          ).to eq("Invalid application type: String")
        end
      end

      context 'when application is not in a copiable state' do
        let(:application_state) { :initial }

        it 'returns failure with error message' do
          expect(
            subject.call(application: application, origin: origin, generation_reason: generation_reason).failure
          ).to eq("Application cannot be copied as it is not in one of the determined, expired states")
        end
      end

      context 'when origin is invalid' do
        let(:origin) { :invalid_origin }

        it 'returns failure with error message' do
          expect(
            subject.call(application: application, origin: origin, generation_reason: generation_reason).failure
          ).to eq('Invalid origin: invalid_origin')
        end
      end

      context 'when generation reason is invalid' do
        let(:generation_reason) { :invalid_reason }

        it 'returns failure with error message' do
          expect(
            subject.call(application: application, origin: origin, generation_reason: generation_reason).failure
          ).to eq('Invalid generation reason: invalid_reason')
        end
      end

      context 'when multiple applicants are present but the depedents are not associated with any family members' do
        let(:person2) do
          per = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
          person.ensure_relationship_with(per, 'spouse')
          per
        end

        let(:member2) { FactoryBot.create(:family_member, family: family, person: person2) }

        let(:applicant2) do
          FactoryBot.create(
            :individual_market_applicant,
            :dependent,
            :with_person_name,
            :with_eligibilities,
            application: application,
            family_member_id: nil # No family member association
          )
        end

        let(:rel1) { FactoryBot.create(:individual_market_relationship, application: application, kind: 'spouse', relative_id: applicant.id, source_id: applicant2.id) }

        before do
          rel1
        end

        it 'returns failure with error message' do
          expect(result.failure).to include("No family_member_id found for applicant with id: #{applicant2.id}")
        end
      end
    end

    context 'with valid params' do
      context 'when applicant has:
        - person name
        - demographics
        - immigration information
        - work address
        - mailing address
        - home address
        - phone number
        - email
        ' do

        it 'returns success' do
          expect(result.success?).to be_truthy
        end

        it 'copies the application' do
          expect(result_application).to be_a(::IndividualMarket::Application)
          expect(result_application.origin).to eq(origin)
          expect(result_application.generation_reason).to eq(generation_reason)
          expect(result_application.predecessor).to eq(application)
        end

        it 'copies the applicant' do
          expect(result_applicant).to be_a(::IndividualMarket::Applicant)
          expect(result_applicant.application).to eq(result_application)
          expect(result_applicant.family_member_id).to eq(applicant.family_member_id)
          expect(result_applicant.is_primary_applicant).to eq(applicant.is_primary_applicant)
          expect(result_applicant.address_same_as_primary).to eq(applicant.address_same_as_primary)
          expect(result_applicant.is_applying_coverage).to eq(applicant.is_applying_coverage)
          expect(result_applicant.is_homeless).to eq(applicant.is_homeless)
          expect(result_applicant.age_off_excluded).to eq(applicant.age_off_excluded)
          expect(result_applicant.contact_method).to eq(applicant.contact_method)
          expect(result_applicant.language_preference).to eq(applicant.language_preference)
        end

        it 'creates the individual market eligibility' do
          expect(result_applicant.eligibilities).to be_present
          expect(result_applicant.eligibilities.size).to eq(1)
          expect(result_applicant.eligibilities.first).to be_a(::Eligibilities::V3::IndividualMarketEligibility)
        end

        it 'copies the person name' do
          expect(result_person_name).to be_a(::PersonName)
          expect(result_person_name.person_nameable).to eq(result_applicant)
          expect(result_person_name.given_name).to eq(person_name.given_name)
          expect(result_person_name.middle_name).to eq(person_name.middle_name)
          expect(result_person_name.family_name).to eq(person_name.family_name)
          expect(result_person_name.name_sfx).to eq(person_name.name_sfx)
          expect(result_person_name.name_pfx).to eq(person_name.name_pfx)
          expect(result_person_name.alternate_name).to eq(person_name.alternate_name)
        end

        it 'copies the demographics' do
          expect(result_demographics).to be_a(::IndividualMarket::Demographics)
          expect(result_demographics.applicant).to eq(result_applicant)
          expect(result_demographics.encrypted_ssn).to eq(demographics.encrypted_ssn)
          expect(result_demographics.no_ssn).to eq(demographics.no_ssn)
          expect(result_demographics.gender).to eq(demographics.gender)
          expect(result_demographics.dob).to eq(demographics.dob)
          expect(result_demographics.is_incarcerated).to eq(demographics.is_incarcerated)
          expect(result_demographics.is_physically_disabled).to eq(demographics.is_physically_disabled)
          expect(result_demographics.indian_tribe_member).to eq(demographics.indian_tribe_member)
          expect(result_demographics.tribal_id).to eq(demographics.tribal_id)
          expect(result_demographics.tribal_name).to eq(demographics.tribal_name)
          expect(result_demographics.tribal_state).to eq(demographics.tribal_state)
          expect(result_demographics.tribe_codes).to eq(demographics.tribe_codes)
          expect(result_demographics.language_code).to eq(demographics.language_code)
          expect(result_demographics.ethnicity).to eq(demographics.ethnicity)
          expect(result_demographics.race).to eq(demographics.race)
          expect(result_demographics.citizen_status).to eq(demographics.citizen_status)
        end

        it 'copies the immigration information' do
          expect(result_immigration_information).to be_a(::IndividualMarket::ImmigrationInformation)
          expect(result_immigration_information.applicant).to eq(result_applicant)
          expect(result_immigration_information.subject).to eq(immigration_information.subject)
          expect(result_immigration_information.alien_number).to eq(immigration_information.alien_number)
          expect(result_immigration_information.i94_number).to eq(immigration_information.i94_number)
          expect(result_immigration_information.visa_number).to eq(immigration_information.visa_number)
          expect(result_immigration_information.passport_number).to eq(immigration_information.passport_number)
          expect(result_immigration_information.sevis_id).to eq(immigration_information.sevis_id)
          expect(result_immigration_information.naturalization_number).to eq(immigration_information.naturalization_number)
          expect(result_immigration_information.receipt_number).to eq(immigration_information.receipt_number)
          expect(result_immigration_information.citizenship_number).to eq(immigration_information.citizenship_number)
          expect(result_immigration_information.card_number).to eq(immigration_information.card_number)
          expect(result_immigration_information.country_of_citizenship).to eq(immigration_information.country_of_citizenship)
          expect(result_immigration_information.expiration_date).to eq(immigration_information.expiration_date)
          expect(result_immigration_information.issuing_country).to eq(immigration_information.issuing_country)
          expect(result_immigration_information.description).to eq(immigration_information.description)
        end

        context 'for addresses' do
          it 'copies the work address' do
            expect(result_work_address).to be_a(::Locations::Address)
            expect(result_work_address.addressable).to eq(result_applicant)
            expect(result_work_address.kind).to eq(work_address.kind)
            expect(result_work_address.address_1).to eq(work_address.address_1)
            expect(result_work_address.address_2).to eq(work_address.address_2)
            expect(result_work_address.address_3).to eq(work_address.address_3)
            expect(result_work_address.city).to eq(work_address.city)
            expect(result_work_address.county).to eq(work_address.county)
            expect(result_work_address.state).to eq(work_address.state)
            expect(result_work_address.zip).to eq(work_address.zip)
            expect(result_work_address.country_name).to eq(work_address.country_name)
            expect(result_work_address.quadrant).to eq(work_address.quadrant)
          end

          it 'copies the mailing address' do
            expect(result_mailing_address).to be_a(::Locations::Address)
            expect(result_mailing_address.addressable).to eq(result_applicant)
            expect(result_mailing_address.kind).to eq(mailing_address.kind)
            expect(result_mailing_address.address_1).to eq(mailing_address.address_1)
            expect(result_mailing_address.address_2).to eq(mailing_address.address_2)
            expect(result_mailing_address.address_3).to eq(mailing_address.address_3)
            expect(result_mailing_address.city).to eq(mailing_address.city)
            expect(result_mailing_address.county).to eq(mailing_address.county)
            expect(result_mailing_address.state).to eq(mailing_address.state)
            expect(result_mailing_address.zip).to eq(mailing_address.zip)
            expect(result_mailing_address.country_name).to eq(mailing_address.country_name)
            expect(result_mailing_address.quadrant).to eq(mailing_address.quadrant)
          end

          it 'copies the home address' do
            expect(result_home_address).to be_a(::Locations::Address)
            expect(result_home_address.addressable).to eq(result_applicant)
            expect(result_home_address.kind).to eq(home_address.kind)
            expect(result_home_address.address_1).to eq(home_address.address_1)
            expect(result_home_address.address_2).to eq(home_address.address_2)
            expect(result_home_address.address_3).to eq(home_address.address_3)
            expect(result_home_address.city).to eq(home_address.city)
            expect(result_home_address.county).to eq(home_address.county)
            expect(result_home_address.state).to eq(home_address.state)
            expect(result_home_address.zip).to eq(home_address.zip)
            expect(result_home_address.country_name).to eq(home_address.country_name)
            expect(result_home_address.quadrant).to eq(home_address.quadrant)
          end
        end

        context 'for emails' do
          it 'copies the email' do
            expect(result_email).to be_a(::Locations::Email)
            expect(result_email.emailable).to eq(result_applicant)
            expect(result_email.kind).to eq(email.kind)
            expect(result_email.address).to eq(email.address)
          end
        end

        context 'for phones' do
          it 'copies the phone' do
            expect(result_phone).to be_a(::Locations::Phone)
            expect(result_phone.phoneable).to eq(result_applicant)
            expect(result_phone.kind).to eq(phone.kind)
            expect(result_phone.country_code).to eq(phone.country_code)
            expect(result_phone.area_code).to eq(phone.area_code)
            expect(result_phone.number).to eq(phone.number)
            expect(result_phone.extension).to eq(phone.extension)
            expect(result_phone.primary).to eq(phone.primary)
          end
        end
      end

      context 'when applicant has:
        - person name
        - demographics
        - NO immigration information
        - work address
        - mailing address
        - home address' do

        let(:result) do
          demographics
          subject.call(
            application: applicant.application,
            origin: origin,
            generation_reason: generation_reason
          )
        end

        it 'returns success without any errors raised' do
          expect(result.success?).to be_truthy
        end
      end

      context 'when applicant has:
        - person name
        - demographics
        - immigration information
        - NO work address
        - NO mailing address
        - home address' do

        let(:applicant) do
          FactoryBot.create(
            :individual_market_applicant,
            :with_person_name,
            :with_eligibilities,
            :with_home_address,
            :with_phone_number,
            :with_email,
            application: application,
            family_member_id: primary_applicant.id
          )
        end

        it 'returns success without any errors raised' do
          expect(result.success?).to be_truthy
        end
      end

      context 'when multiple applicants are present' do
        let(:person2) do
          per = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
          person.ensure_relationship_with(per, 'spouse')
          per
        end
        let(:member2) { FactoryBot.create(:family_member, family: family, person: person2) }

        let(:applicant2) do
          FactoryBot.create(
            :individual_market_applicant,
            :dependent,
            :with_person_name,
            :with_eligibilities,
            :with_work_address,
            :with_mailing_address,
            :with_home_address,
            :with_phone_number,
            :with_email,
            application: application,
            family_member_id: member2.id
          )
        end

        let(:person3) do
          per = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
          person.ensure_relationship_with(per, 'child')
          per
        end
        let(:member3) { FactoryBot.create(:family_member, family: family, person: person3) }

        let(:applicant3) do
          FactoryBot.create(
            :individual_market_applicant,
            :dependent,
            :with_person_name,
            :with_eligibilities,
            :with_work_address,
            :with_mailing_address,
            :with_home_address,
            :with_phone_number,
            :with_email,
            application: application,
            family_member_id: member3.id
          )
        end

        let(:rel1) { FactoryBot.create(:individual_market_relationship, application: application, kind: 'spouse', relative_id: applicant.id, source_id: applicant2.id) }
        let(:rel2) { FactoryBot.create(:individual_market_relationship, application: application, kind: 'child', relative_id: applicant.id, source_id: applicant3.id) }

        before do
          rel1
          rel2
        end

        it 'copies all applicants' do
          expect(result.success?).to be_truthy
          expect(result_application.applicants.size).to eq(3)

          expect(result_application.applicants.map(&:family_member_id)).to contain_exactly(
            primary_applicant.id, member2.id, member3.id
          )

          expect(result_application.applicants.map(&:person_name).map(&:full_name)).to contain_exactly(
            person_name.full_name, applicant2.person_name.full_name, applicant3.person_name.full_name
          )
        end

        it 'copies all relationships' do
          expect(result_application.relationships.size).to eq(2)
          expect(result_application.relationships.map(&:kind)).to contain_exactly('spouse', 'child')
          expect(result_application.relationships.map(&:source).map(&:family_member_id)).to contain_exactly(
            applicant2.family_member_id, applicant3.family_member_id
          )
          expect(result_application.relationships.map(&:relative).map(&:family_member_id)).to contain_exactly(
            applicant.family_member_id, applicant.family_member_id
          )
        end
      end
    end
  end
end
