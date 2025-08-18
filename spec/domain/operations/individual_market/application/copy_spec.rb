# frozen_string_literal: true

RSpec.describe Operations::IndividualMarket::Application::Copy, dbclean: :after_each do

  describe '#call' do
    let(:hbx_profile) { FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period) }
    let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }

    let(:person) do
      per = FactoryBot.create(:person, :with_ssn, :with_consumer_role, :with_active_consumer_role)
      per.addresses.clear
      per.phones.clear
      per.emails.clear
      per.employee_roles.clear
      per.citizen_status = 'us_citizen'
      per.save!
      per
    end
    let(:address1) { FactoryBot.create(:address, person: person, kind: 'work') }
    let(:address2) { FactoryBot.create(:address, person: person, kind: 'mailing') }
    let(:address3) { FactoryBot.create(:address, person: person, kind: 'home') }
    let(:phone1) { FactoryBot.create(:phone, person: person, kind: 'home') }
    let(:phone2) { FactoryBot.create(:phone, person: person, kind: 'mobile') }
    let(:email1) { FactoryBot.create(:email, person: person, kind: 'home') }
    let(:email2) { FactoryBot.create(:email, person: person, kind: 'work') }

    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:primary_applicant) { family.primary_applicant }

    let(:application_state) { :determined }
    let(:current_application) { FactoryBot.create(:individual_market_application, family: family, current_state: application_state) }

    before :each do
      benefit_sponsorship
    end

    context 'when:
      - input application is nil
      ' do

      it 'returns failure with error message' do
        result = subject.call(application: nil, origin: :system, generation_reason: :manual)
        expect(result.failure).to eq("Invalid application type: NilClass")
      end
    end

    context 'when:
      - input application is not in copyable state
      ' do
      let(:application_state) { :initial }

      it 'returns failure with error message' do
        result = subject.call(application: current_application, origin: :system, generation_reason: :manual)
        expect(result.failure).to eq('Application cannot be copied as it is not in one of the determined, expired states')
      end
    end

    context 'when:
      - input application is in copyable state (determined)
      - family has one family member
      - person has emails, phones, and addresses
      ' do

      before :each do
        address1
        address2
        address3
        phone1
        phone2
        email1
        email2
      end

      let(:result) { subject.call(application: current_application, origin: :system, generation_reason: :manual) }
      let(:new_application) { result.value! }
      let(:new_applicant1) { new_application.applicants.where(family_member_id: primary_applicant.id).first }

      it 'creates a new application' do
        expect(result.success?).to be_truthy
        expect(new_application).to be_a(IndividualMarket::Application)
        expect(new_application.predecessor_id).to eq(current_application.id)
      end

      it 'creates applicants for all the family members' do
        expect(new_application.applicants.count).to eq(family.active_family_members.count)
        new_application.applicants.each do |appli|
          expect(family.active_family_members.map(&:id)).to include(appli.family_member_id)
        end
      end

      it 'copies the names' do
        expect(new_applicant1.person_name).to have_attributes(
          given_name: person.first_name,
          family_name: person.last_name
        )
      end

      it 'copies the addresses' do
        expect(new_applicant1.mailing_address).to have_attributes(
          kind: 'mailing',
          address_1: address2.address_1,
          address_2: address2.address_2,
          city: address2.city,
          state: address2.state,
          zip: address2.zip
        )

        expect(new_applicant1.home_address).to have_attributes(
          kind: 'home',
          address_1: address3.address_1,
          address_2: address3.address_2,
          city: address3.city,
          state: address3.state,
          zip: address3.zip
        )

        expect(new_applicant1.work_address).to have_attributes(
          kind: 'work',
          address_1: address1.address_1,
          address_2: address1.address_2,
          city: address1.city,
          state: address1.state,
          zip: address1.zip
        )
      end

      it 'copies the phone numbers' do
        expect(new_applicant1.phones.count).to eq(2)
        expect(new_applicant1.home_phone).to have_attributes(
          kind: 'home',
          number: phone1.number
        )

        expect(new_applicant1.mobile_phone).to have_attributes(
          kind: 'mobile',
          number: phone2.number
        )
      end

      it 'copies the email addresses' do
        expect(new_applicant1.emails.count).to eq(2)

        expect(new_applicant1.home_email).to have_attributes(
          kind: 'home',
          address: email1.address
        )

        expect(new_applicant1.work_email).to have_attributes(
          kind: 'work',
          address: email2.address
        )
      end
    end

    context 'when:
      - input application is in copyable state (determined)
      - family has more than one family member
      ' do

      let(:person2) do
        per = FactoryBot.create(:person, :with_ssn, :with_consumer_role, :with_active_consumer_role)
        per.addresses.clear
        per.phones.clear
        per.emails.clear
        per.employee_roles.clear
        per.citizen_status = 'us_citizen'
        per.save!
        person.ensure_relationship_with(per, 'spouse')
        person.save!
        per
      end
      let(:family_member2) { FactoryBot.create(:family_member, family: family, person: person2) }

      before :each do
        address1
        address2
        address3
        phone1
        phone2
        email1
        email2
        family_member2
      end

      let(:result) { subject.call(application: current_application, origin: :system, generation_reason: :manual) }
      let(:new_application) { result.value! }
      let(:new_applicant1) { new_application.applicants.where(family_member_id: primary_applicant.id).first }
      let(:new_applicant2) { new_application.applicants.where(family_member_id: family_member2.id).first }

      it 'creates a new application' do
        expect(result.success?).to be_truthy
        expect(new_application).to be_a(IndividualMarket::Application)
        expect(new_application.predecessor_id).to eq(current_application.id)
      end

      it 'creates applicants for all the family members' do
        expect(new_application.applicants.count).to eq(family.active_family_members.count)
        new_application.applicants.each do |appli|
          expect(family.active_family_members.map(&:id)).to include(appli.family_member_id)
        end
      end

      it 'creates relationships' do
        expect(new_application.relationships.first).to have_attributes(
          source_id: new_applicant2.id,
          relative_id: new_applicant1.id,
          kind: 'spouse'
        )
      end

      it 'copies the names' do
        expect(new_applicant1.person_name).to have_attributes(
          given_name: person.first_name,
          family_name: person.last_name
        )

        expect(new_applicant2.person_name).to have_attributes(
          given_name: person2.first_name,
          family_name: person2.last_name
        )
      end

      it 'copies the addresses' do
        expect(new_applicant1.mailing_address).to have_attributes(
          kind: 'mailing',
          address_1: address2.address_1,
          address_2: address2.address_2,
          city: address2.city,
          state: address2.state,
          zip: address2.zip
        )

        expect(new_applicant1.home_address).to have_attributes(
          kind: 'home',
          address_1: address3.address_1,
          address_2: address3.address_2,
          city: address3.city,
          state: address3.state,
          zip: address3.zip
        )

        expect(new_applicant1.work_address).to have_attributes(
          kind: 'work',
          address_1: address1.address_1,
          address_2: address1.address_2,
          city: address1.city,
          state: address1.state,
          zip: address1.zip
        )

        expect(new_applicant2.addresses.count).to eq(person2.addresses.count)
      end

      it 'copies the phone numbers' do
        expect(new_applicant1.phones.count).to eq(2)
        expect(new_applicant1.home_phone).to have_attributes(
          kind: 'home',
          number: phone1.number
        )

        expect(new_applicant1.mobile_phone).to have_attributes(
          kind: 'mobile',
          number: phone2.number
        )

        expect(new_applicant2.phones.count).to eq(person2.phones.count)
      end

      it 'copies the email addresses' do
        expect(new_applicant1.emails.count).to eq(2)

        expect(new_applicant1.home_email).to have_attributes(
          kind: 'home',
          address: email1.address
        )

        expect(new_applicant1.work_email).to have_attributes(
          kind: 'work',
          address: email2.address
        )

        expect(new_applicant2.emails.count).to eq(person2.emails.count)
      end
    end
  end
end
