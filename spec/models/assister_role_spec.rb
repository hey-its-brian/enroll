# frozen_string_literal: true

require 'rails_helper'

describe AssisterRole, dbclean: :around_each do

  let(:address) {FactoryBot.build(:address)}
  let(:saved_person) {FactoryBot.create(:person, addresses: [address])}
  let(:person0) {FactoryBot.create(:person)}
  let(:person1) {FactoryBot.create(:person)}
  let(:assister_org_id0) {"7775566"}
  let(:assister_org_id1) {"48484848"}
  let(:provider_kind)  {"assister"}

  describe ".new" do
    let(:valid_params) do
      {
        person: saved_person,
        assister_org_id: assister_org_id0,
        provider_kind: provider_kind
      }
    end

    context "with no arguments" do
      let(:params) {{}}

      it "should not save" do
        expect(AssisterRole.new(**params).save).to be_falsey
      end
    end

    context "with no person" do
      let(:params) {valid_params.except(:person)}

      it "should raise" do
        expect{AssisterRole.create(**params)}.to raise_error(Mongoid::Errors::NoParent)
      end
    end

    context "with no assister_org_id" do
      let(:params) {valid_params.except(:assister_org_id)}

      it "should fail validation" do
        expect(AssisterRole.create(**params).errors[:assister_org_id].any?).to be_truthy
      end
    end

    context "with no provider_kind" do
      let(:params) {valid_params.except(:provider_kind)}

      it "should fail validation" do
        expect(AssisterRole.create(**params).errors[:provider_kind].any?).to be_truthy
      end
    end

    context "with all required data" do
      let(:assister_role) {saved_person.build_assister_role(valid_params)}

      it "should save" do
        expect(assister_role.save).to be_truthy
      end

      context "and it is saved" do
        before do
          assister_role.save
        end

        it "should be findable" do
          expect(AssisterRole.find(assister_role.id).id.to_s).to eq assister_role.id.to_s
        end
      end
    end

    context "decertify" do
      let(:person) { FactoryBot.create(:person, :with_work_email)}
      let(:family) { FactoryBot.create(:family, :with_primary_family_member,person: person) }
      let(:assister_agency_profile) { FactoryBot.build(:benefit_sponsors_organizations_assister_agency_profile)}
      let(:writing_agent)  do
        FactoryBot.create(:assister_role,
                          benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id,
                          aasm_state: "active")
      end

      before do
        writing_agent.update!(:benefit_sponsors_assister_agency_profile_id => assister_agency_profile.id)
        family.assister_agency_accounts << BenefitSponsors::Accounts::AssisterAgencyAccount.new(benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id,
                                                                                                writing_agent_id: writing_agent.id,
                                                                                                start_on: Time.now,
                                                                                                is_active: true)
      end

      it "should trigger assister fired event on a family" do
        #expect_any_instance_of(Events::Family::Assisters::AssisterFired).to receive(:publish)
        writing_agent.decertify!
      end
    end

    context "validate uniqueness of assister_org_id" do
      let!(:assister_person) { FactoryBot.create(:person)}
      let!(:assister_role) {FactoryBot.build(:assister_role, assister_org_id: "7775588", person: assister_person, provider_kind: provider_kind)}

      it { should validate_uniqueness_of(:assister_org_id) }

      it "validate uniqueness of assister_org_id" do
        expect(assister_role.valid?).to be_truthy
      end
    end

    context 'allow_alphanumeric_assister_org_id' do
      let(:person) { FactoryBot.create(:person, :with_work_email)}
      let(:assister_agency_profile) { FactoryBot.build(:benefit_sponsors_organizations_assister_agency_profile)}
      let(:assister_role) { FactoryBot.create(:assister_role, assister_org_id: "7775588", person: person, provider_kind: provider_kind) }
      let(:new_assister_org_id) { 'abc1234567' }

      context 'allow_alphanumeric_assister_org_id enabled' do
        before do
          allow(EnrollRegistry[:allow_alphanumeric_npn].feature).to receive(:is_enabled).and_return(true)
        end

        it 'saves allow_alphanumeric' do
          expect(assister_role.update_attributes(assister_org_id: new_assister_org_id)).to eq true
          expect(assister_role.reload.assister_org_id).to eq new_assister_org_id
        end
      end

      context 'allow_alphanumeric_assister_org_id disabled' do
        before do
          allow(EnrollRegistry[:allow_alphanumeric_npn].feature).to receive(:is_enabled).and_return(false)
        end

        it 'saves allow_alphanumeric' do
          expect(assister_role.update_attributes(assister_org_id: new_assister_org_id)).to eq false
          expect(assister_role.reload.assister_org_id).not_to eq new_assister_org_id
        end
      end
    end

    context "a assister registers" do
      let(:person)  { FactoryBot.build(:person, :with_work_email) }
      let(:assister_agency_profile) { FactoryBot.build(:benefit_sponsors_organizations_assister_agency_profile)}
      let(:registered_assister_role) { AssisterRole.new(person: person, assister_org_id: "2323334", provider_kind: "assister", benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id) }

      it "should initialize to applicant state" do
        expect(registered_assister_role.valid?).to be_truthy
        expect(registered_assister_role.aasm_state).to eq "applicant"
      end

      it "should record the transition" do
        expect(registered_assister_role.workflow_state_transitions.size).to eq 1
        expect(registered_assister_role.workflow_state_transitions.first.from_state).to be_nil
        expect(registered_assister_role.workflow_state_transitions.first.to_state).to eq "applicant"
      end

      context "and is approved by the HBX" do
        before do
          allow(registered_assister_role).to receive(:is_primary_assister?).and_return(true)
          registered_assister_role.approve
        end

        it "should transition to active status" do
          expect(registered_assister_role.aasm_state).to eq "active"
        end

        it "should record the transition" do
          expect(registered_assister_role.workflow_state_transitions.size).to eq 2
          expect(registered_assister_role.workflow_state_transitions.last.from_state).to eq "applicant"
          expect(registered_assister_role.workflow_state_transitions.last.to_state).to eq "active"
        end

        context "and is then decertified by the HBX" do
          before do
            registered_assister_role.decertify
          end

          it "should transition to decertified status" do
            expect(registered_assister_role.aasm_state).to eq "decertified"
          end

          it "should record the transition" do
            expect(registered_assister_role.workflow_state_transitions.size).to eq 3
            expect(registered_assister_role.workflow_state_transitions.last.from_state).to eq "active"
            expect(registered_assister_role.workflow_state_transitions.last.to_state).to eq "decertified"
          end

          context "should be able to recertify" do
            before do
              registered_assister_role.recertify
            end

            it "should transition to active status" do
              expect(registered_assister_role.aasm_state).to eq "active"
            end

            it "should record the transition" do
              expect(registered_assister_role.workflow_state_transitions.size).to eq 4
              expect(registered_assister_role.workflow_state_transitions.last.from_state).to eq "decertified"
              expect(registered_assister_role.workflow_state_transitions.last.to_state).to eq "active"
            end
          end
        end
      end

      context "and is denied by the HBX" do

        it "should transition to denied status" do
          registered_assister_role.deny
          expect(registered_assister_role.aasm_state).to eq "denied"
        end

        it "should record the transition" do
          registered_assister_role.deny
          expect(registered_assister_role.workflow_state_transitions.size).to eq 2
          expect(registered_assister_role.workflow_state_transitions.last.from_state).to eq "applicant"
          expect(registered_assister_role.workflow_state_transitions.last.to_state).to eq "denied"
        end

        it 'should transition from application_extended to denied' do
          registered_assister_role.update_attributes(aasm_state: 'application_extended')
          registered_assister_role.deny
        end
      end

      context 'extend assister application' do

        it 'should transition denied assister to application_extended' do
          registered_assister_role.deny!
          registered_assister_role.extend_application!
          expect(registered_assister_role.aasm_state).to eq 'application_extended'
        end

        it 'should transition pending assister to application_extended' do
          allow(registered_assister_role).to receive(:is_primary_assister?).and_return(true)
          registered_assister_role.pending!
          registered_assister_role.extend_application!
          expect(registered_assister_role.aasm_state).to eq 'application_extended'
        end

        it 'should transition application_extended assister to application_extended' do
          allow(registered_assister_role).to receive(:is_primary_assister?).and_return(true)
          registered_assister_role.pending!
          registered_assister_role.extend_application!
          registered_assister_role.extend_application!
          expect(registered_assister_role.aasm_state).to eq 'application_extended'
        end
      end

      context 'assister agency accept' do
        before :each do
          allow(registered_assister_role).to receive(:is_primary_assister?).and_return(true)
        end

        it "should transition from assister_agency_pending to active status" do
          registered_assister_role.pending!
          registered_assister_role.assister_agency_accept!
          expect(registered_assister_role.aasm_state).to eq "active"
        end

        it "should transition from application_extended to active status" do
          registered_assister_role.pending!
          registered_assister_role.extend_application!
          registered_assister_role.assister_agency_accept!
          expect(registered_assister_role.aasm_state).to eq "active"
        end
      end

      context "assister agency pending" do
        before do
          allow(registered_assister_role).to receive(:is_primary_assister?).and_return(true)
          registered_assister_role.pending
        end

        it "should transition to pending status" do
          expect(registered_assister_role.aasm_state).to eq "assister_agency_pending"
        end

        it "should record the transition" do
          expect(registered_assister_role.workflow_state_transitions.size).to eq 2
          expect(registered_assister_role.workflow_state_transitions.last.from_state).to eq "applicant"
          expect(registered_assister_role.workflow_state_transitions.last.to_state).to eq "assister_agency_pending"
        end
      end
    end
  end

  describe AssisterRole, '.find_by_assister_org_id', :dbclean => :around_each do
    it 'returns Assister instance for the specified National Producer Number' do
      b0 = AssisterRole.create(person: person0, assister_org_id: assister_org_id0, provider_kind: provider_kind)
      AssisterRole.create(person: person1, assister_org_id: assister_org_id1, provider_kind: provider_kind)

      expect(AssisterRole.find_by_assister_org_id(assister_org_id0).assister_org_id).to eq b0.assister_org_id
    end
  end

  describe AssisterRole, '.find_by_assister_agency_profile', :dbclean => :around_each do
    before :each do
      @ba = FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile, primary_assister_role: nil)
    end

    it 'returns Assister instance for the specified National Producer Number' do
      AssisterRole.create(person: person0, assister_org_id: assister_org_id0, provider_kind: provider_kind, assister_agency_profile: @ba)
      AssisterRole.create(person: person1, assister_org_id: assister_org_id1, provider_kind: provider_kind, assister_agency_profile: @ba)

      expect(AssisterRole.find_by_assister_agency_profile(@ba).size).to eq 2
      expect(AssisterRole.find_by_assister_agency_profile(@ba).first.benefit_sponsors_assister_agency_profile_id).to eq @ba._id
    end
  end

  # Instance methods
  describe AssisterRole, :dbclean => :around_each do
    before :all do
      @ba = FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile)
    end

    it '#assister_agency_profile sets agency' do
      expect(AssisterRole.new(assister_agency_profile: @ba).assister_agency_profile.id).to eq @ba._id
    end

    it '#has_assister_agency_profile? is true when agency is assigned' do
      expect(AssisterRole.new(assister_agency_profile: nil).has_assister_agency_profile?).to be_falsey
      expect(AssisterRole.new(assister_agency_profile: @ba).has_assister_agency_profile?).to be_truthy
    end

    context '#email returns work email' do
      person0 = FactoryBot.create(:person)
      provider_kind = 'assister'

      b1 = AssisterRole.create(person: person0, assister_org_id: rand(10_000_000..10_009_999), provider_kind: provider_kind, assister_agency_profile: @ba)
      it "#email returns nil if no work email" do
        expect(b1.email).to be_nil
      end
      it '#email returns an instance of email with kind==work' do
        person0.emails[1].update_attributes(kind: 'work')
        expect(b1.email).to be_an_instance_of(Email)
        expect(b1.email.kind).to eq('work')
      end
    end

    context '#phone returns assister office phone or agency office phone or work phone' do
      person0 = FactoryBot.create(:person)
      provider_kind = 'assister'

      it 'should return assister agency profile phone' do
        b1 = AssisterRole.create(person: person0, assister_org_id: rand(10_000_000..10_009_999), provider_kind: provider_kind, assister_agency_profile: @ba)
        expect(b1.phone.to_s).to eq b1.assister_agency_profile.phone
      end
      it 'should return work phone' do
        b1 = AssisterRole.create(person: person0, assister_org_id: rand(10_000_000..10_009_999), provider_kind: provider_kind, assister_agency_profile: @ba)
        person0.phones[1].update_attributes!(kind: 'work')
        expect(b1.phone.to_s).not_to eq b1.assister_agency_profile.phone
        expect(b1.phone.to_s).to eq person0.phones.where(kind: "work").first.to_s
      end

      it 'should return work phone if office phone & assister agency profile phone not present' do
        b1 = AssisterRole.create(person: person0, assister_org_id: rand(10_000_000..10_009_999), provider_kind: provider_kind, assister_agency_profile: @ba)
        allow(b1.assister_agency_profile).to receive(:phone).and_return nil
        person0.phones[1].update_attributes!(kind: 'work')
        expect(b1.phone.to_s).not_to eq b1.assister_agency_profile.phone
        expect(b1.phone.to_s).to eq person0.phones.where(kind: "work").first.to_s
      end
    end
  end
end
