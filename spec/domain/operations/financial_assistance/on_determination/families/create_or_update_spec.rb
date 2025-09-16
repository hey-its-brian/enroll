# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::FinancialAssistance::OnDetermination::Families::CreateOrUpdate, type: :model, dbclean: :after_each do
  let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }
  let(:primary_applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      is_primary_applicant: true,
      family_member_id: primary_family_member_id,
      person_hbx_id: primary_person.hbx_id,
      eligibility_determination_id: determination.id,
      addresses: [primary_address],
      emails: [primary_email],
      phones: [primary_phone],
      application: application,
      gender: 'female'
    )
  end
  let(:determination) { FactoryBot.create(:financial_assistance_eligibility_determination, application: application) }

  let(:primary_email) { FactoryBot.build(:financial_assistance_email, kind: 'home', address: primary_email_1) }

  let(:primary_email_1) { 'primary_email@home.com' }

  let(:primary_phone) { FactoryBot.build(:financial_assistance_phone, kind: 'home', area_code: '098', number: primary_phone_number) }

  let(:primary_phone_number) { '7654321' }

  let(:primary_address_1) { '123 New Testing St' }

  let(:primary_address) do
    FactoryBot.build(
      :financial_assistance_address,
      kind: 'home',
      address_1: primary_address_1,
      city: 'Washington',
      state: 'DC',
      zip: '20001'
    )
  end

  let(:secondary_applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      is_primary_applicant: false,
      family_member_id: secondary_family_member_id,
      person_hbx_id: secondary_person_hbx_id,
      eligibility_determination_id: determination.id,
      addresses: [secondary_address],
      emails: [secondary_email],
      phones: [secondary_phone],
      application: application,
      gender: 'female'
    )
  end

  let(:secondary_email) { FactoryBot.build(:financial_assistance_email, kind: 'home', address: 'secondary_email@home.com') }
  let(:secondary_phone) { FactoryBot.build(:financial_assistance_phone, kind: 'home', area_code: '123', number: '4567890') }

  let(:secondary_address) do
    FactoryBot.build(
      :financial_assistance_address,
      kind: 'home',
      address_1: '456 Testing St',
      city: 'Washington',
      state: 'DC',
      zip: '20001'
    )
  end

  let(:relationship) { application.relationships.create(applicant_id: primary_applicant.id, relative_id: secondary_applicant.id, kind: 'spouse') }
  let(:inverse_relationship) { application.relationships.create(applicant_id: secondary_applicant.id, relative_id: primary_applicant.id, kind: 'spouse') }

  let(:primary_person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) {  FactoryBot.create(:family, :with_primary_family_member, person: primary_person) }
  let(:primary_family_member_id) { family.primary_applicant.id }
  let(:returned_family) { @result.success[1] }
  let(:returned_thhg) { returned_family.tax_household_groups.first }

  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
  end

  describe '#call' do
    # Deactivation of a family member who is not present on the application
    context "when:
      - primary applicant's family member and person exists
      - primary_applicant's information is different from the existing person
      - secondary applicant does not exist
      - dependent family member with person exists
    " do

      let(:secondary_person) do
        per = FactoryBot.create(:person, :with_consumer_role)
        primary_person.person_relationships.create(relative_id: per.id, kind: 'child')
        per
      end
      let(:secondary_person_hbx_id) { secondary_person.hbx_id }
      let(:secondary_family_member) { FactoryBot.create(:family_member, family: family, person: secondary_person) }
      let(:secondary_family_member_id) { secondary_family_member.id }

      before :each do
        secondary_family_member
        primary_applicant.application.build_aptc_eligibilities_evidences
        application.build_ivl_eligibility_with_evidences
        application.save!
        @result = subject.call(application: application)
        primary_person.reload
        secondary_person.reload
        family.reload
        application.reload
      end

      it 'returns a success result' do
        expect(@result.success?).to be_truthy
      end

      it 'assigns latest application GID' do
        expect(family.latest_application_gid).to eq(application.to_global_id.uri.to_s)
      end

      it "updates the primary person's gender" do
        expect(primary_person.gender).to eq('female')
      end

      it 'deactivates the secondary family member' do
        expect(secondary_family_member.reload.is_active).to be_falsey
      end

      it 'removes coverage household member for the deleted family member' do
        member_ids = family.reload.active_household.coverage_households.first.coverage_household_members.map(&:family_member_id)
        expect(member_ids).not_to include(secondary_family_member.id)
      end

      it 'updates applicants with family_member_id and person_hbx_id' do
        application.applicants.each do |applicant|
          expect(applicant.family_member_id).to be_present
          expect(applicant.person_hbx_id).to be_present
        end
      end

      it 'updates the application with family_updated_at' do
        expect(application.family_updated_at).to be_present
      end
    end

    context "relationships/vlp documents" do
      let(:third_applicant) do
        FactoryBot.create(
          :financial_assistance_applicant,
          is_primary_applicant: false,
          eligibility_determination_id: determination.id,
          addresses: [secondary_address],
          emails: [secondary_email],
          phones: [secondary_phone],
          application: application,
          gender: 'female'
        )
      end

      let(:third_applicant_relationship) { application.relationships.create(applicant_id: third_applicant.id, relative_id: primary_applicant.id, kind: 'child') }
      let(:third_applicant_inverse_relationship) { application.relationships.create(applicant_id: primary_applicant.id, relative_id: third_applicant.id, kind: 'parent') }


      before :each do
        third_applicant_relationship
        third_applicant_inverse_relationship
        primary_applicant.application.build_aptc_eligibilities_evidences
        third_applicant.application.build_ivl_eligibility_with_evidences
        application.build_ivl_eligibility_with_evidences
        application.save!
        @result = subject.call(application: application)
        primary_person.reload
        third_applicant.reload
        family.reload
        application.reload
      end

      it 'returns a success result' do
        expect(@result.success?).to be_truthy
      end

      it 'assigns latest application GID' do
        expect(family.latest_application_gid).to eq(application.to_global_id.uri.to_s)
      end

      it 'updates the relationship kind' do
        third_person = third_applicant.family_member.person
        expect(primary_person.person_relationships.where(relative_id: third_person.id).first.kind).to eq('child')
      end

      it 'should not create vlp document for secondary person' do
        third_person = third_applicant.family_member.person
        expect(third_person.consumer_role.vlp_documents.size).to eq(0)
      end

      it 'should set is_applicant status on consumer role' do
        third_person = third_applicant.family_member.person
        expect(third_person.consumer_role.is_applicant).to eq(third_applicant.is_primary_applicant)
      end
    end

    context "when:
      - primary applicant's family member and person exists
      - primary_applicant's information is different from the existing person
      - secondary applicant's family member and person exists
      - secondary_applicant's information is different from the existing person" do

      let(:secondary_person) do
        per = FactoryBot.create(:person, :with_consumer_role)
        primary_person.person_relationships.create(relative_id: per.id, kind: 'child')
        per
      end
      let(:secondary_person_hbx_id) { secondary_person.hbx_id }
      let(:secondary_family_member) { FactoryBot.create(:family_member, family: family, person: secondary_person) }
      let(:secondary_family_member_id) { secondary_family_member.id }

      before :each do
        relationship.application.build_aptc_eligibilities_evidences
        inverse_relationship
        application.build_ivl_eligibility_with_evidences
        application.save!
        @result = subject.call(application: application)
        primary_person.reload
        secondary_person.reload
        family.reload
        application.reload
      end

      it 'returns a success result' do
        expect(@result.success?).to be_truthy
      end

      it 'should create evidences for primary and secondary person' do
        primary_subject = family.eligibility_determination.subjects.detect{|subject| subject.hbx_id == primary_person.hbx_id}
        secondary_subject = family.eligibility_determination.subjects.detect{|subject| subject.hbx_id == secondary_person.hbx_id}
        expect(primary_subject.aptc_csr_eligibility_state.evidence_states).to be_present
        expect(secondary_subject.aptc_csr_eligibility_state.evidence_states).to be_present
      end

      it 'assigns latest application GID' do
        expect(family.latest_application_gid).to eq(application.to_global_id.uri.to_s)
      end

      it "updates the primary person's gender" do
        expect(primary_person.gender).to eq('female')
      end

      it 'updates the relationship kind' do
        expect(primary_person.person_relationships.where(relative_id: secondary_person.id).first.kind).to eq('spouse')
      end

      it 'creates tax household group for the family' do
        expect(returned_family.tax_household_groups.size).to eq(1)
        expect(returned_family.tax_household_groups.first).to be_a(TaxHouseholdGroup)

        expect(returned_thhg).to have_attributes(
          source: 'Faa',
          application_gid: application.to_global_id.to_s,
          start_on: application.effective_date,
          end_on: nil,
          assistance_year: application.assistance_year
        )
      end

      it 'updates primary person with new address and removes old addresses' do
        expect(primary_person.addresses.size).to eq(1)
        expect(primary_person.addresses.first).to have_attributes(
          kind: primary_address.kind,
          address_1: primary_address.address_1,
          city: primary_address.city,
          state: primary_address.state,
          zip: primary_address.zip
        )
      end

      it 'updates primary person with new email and removes old emails' do
        expect(primary_person.emails.size).to eq(1)
        expect(primary_person.emails.first).to have_attributes(
          kind: primary_email.kind,
          address: primary_email.address
        )
      end

      it 'updates primary person with new phone and removes the old phones' do
        expect(primary_person.phones.size).to eq(1)
        expect(primary_person.phones.first).to have_attributes(
          kind: primary_phone.kind,
          area_code: primary_phone.area_code,
          number: primary_phone.number
        )
      end

      it "updates the secondary person's gender" do
        expect(secondary_person.gender).to eq('female')
      end

      it 'updates secondary person with new address and removes old addresses' do
        expect(secondary_person.addresses.size).to eq(1)
        expect(secondary_person.addresses.first).to have_attributes(
          kind: secondary_address.kind,
          address_1: secondary_address.address_1,
          city: secondary_address.city,
          state: secondary_address.state,
          zip: secondary_address.zip
        )
      end

      it 'updates secondary person with new email and removes old emails' do
        expect(secondary_person.emails.size).to eq(1)
        expect(secondary_person.emails.first).to have_attributes(
          kind: secondary_email.kind,
          address: secondary_email.address
        )
      end

      it 'updates secondary person with new phone and removes the old phones' do
        expect(secondary_person.phones.size).to eq(1)
        expect(secondary_person.phones.first).to have_attributes(
          kind: secondary_phone.kind,
          area_code: secondary_phone.area_code,
          number: secondary_phone.number
        )
      end

      it 'updates applicants with family_member_id and person_hbx_id' do
        application.applicants.each do |applicant|
          expect(applicant.family_member_id).to be_present
          expect(applicant.person_hbx_id).to be_present
        end
      end

      it 'updates the application with family_updated_at' do
        expect(application.family_updated_at).to be_present
      end
    end

    context "when:
      - primary applicant's family member and person exists
      - primary_applicant's information is different from the existing person
      - secondary applicant's family member and person does not exist" do
      let(:new_family_member) { returned_family.family_members.where(id: secondary_applicant.reload.family_member_id).first }

      let(:new_person) { new_family_member.person }

      let(:secondary_person_hbx_id) { nil }
      let(:secondary_family_member_id) { nil }

      before :each do
        allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)

        relationship.application.build_aptc_eligibilities_evidences
        inverse_relationship
        application.build_ivl_eligibility_with_evidences
        application.save!
        @result = subject.call(application: application)
        primary_person.reload
        family.reload
        application.reload
      end

      it 'returns a success result' do
        expect(@result.success?).to be_truthy
      end

      it 'assigns latest application GID' do
        expect(family.latest_application_gid).to eq(application.to_global_id.uri.to_s)
      end

      it 'updates the secondary applicant with the new family member id' do
        expect(family.family_members.map(&:id)).to include(secondary_applicant.family_member_id)
      end

      it 'creates a coverage household member for the applicant' do
        member_ids = family.active_household.coverage_households.first.coverage_household_members.map(&:family_member_id)
        expect(member_ids).to include(secondary_applicant.family_member_id)
      end

      it "updates the existing person's gender" do
        expect(primary_person.gender).to eq('female')
      end

      it 'updates existing person with new address and removes old addresses' do
        expect(primary_person.addresses.size).to eq(1)
        expect(primary_person.addresses.first).to have_attributes(
          kind: primary_address.kind,
          address_1: primary_address.address_1,
          city: primary_address.city,
          state: primary_address.state,
          zip: primary_address.zip
        )
      end

      it 'updates existing person with new email and removes old emails' do
        expect(primary_person.emails.size).to eq(1)
        expect(primary_person.emails.first).to have_attributes(
          kind: primary_email.kind,
          address: primary_email.address
        )
      end

      it 'updates existing person with new phone and removes the old phones' do
        expect(primary_person.phones.size).to eq(1)
        expect(primary_person.phones.first).to have_attributes(
          kind: primary_phone.kind,
          area_code: primary_phone.area_code,
          number: primary_phone.number
        )
      end

      it 'creates a new active family member for the secondary applicant' do
        expect(new_family_member).to be_a(FamilyMember)
        expect(secondary_applicant.family_member_id).to eq(new_family_member.id)
        expect(secondary_applicant.person_hbx_id).to eq(new_person.hbx_id)
        expect(new_family_member.is_active).to be_truthy
      end

      it 'creates addresses for the new person' do
        expect(new_person.addresses.size).to eq(1)
        expect(new_person.addresses.first).to have_attributes(
          kind: secondary_address.kind,
          address_1: secondary_address.address_1,
          city: secondary_address.city,
          state: secondary_address.state,
          zip: secondary_address.zip
        )
      end

      it 'creates emails for the new person' do
        expect(new_person.emails.size).to eq(1)
        expect(new_person.emails.first).to have_attributes(
          kind: secondary_email.kind,
          address: secondary_email.address
        )
      end

      it 'creates phones for the new person' do
        expect(new_person.phones.size).to eq(1)
        expect(new_person.phones.first).to have_attributes(
          kind: secondary_phone.kind,
          area_code: secondary_phone.area_code,
          number: secondary_phone.number
        )
      end

      it 'creates a demographics group for the new person' do
        expect(new_person.demographics_group).to be_present
        expect(new_person.demographics_group.alive_status.is_deceased).to eq false
      end

      it 'updates applicants with family_member_id and person_hbx_id' do
        application.applicants.each do |applicant|
          expect(applicant.family_member_id).to be_present
          expect(applicant.person_hbx_id).to be_present
        end
      end

      it 'updates the application with family_updated_at' do
        expect(application.family_updated_at).to be_present
      end
    end
  end
end
