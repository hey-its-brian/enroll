# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndividualMarket::Application, type: :model do
  let(:application) { FactoryBot.create(:individual_market_application, :with_primary) }

  describe 'associations' do
    it 'belongs to a family' do
      expect(application.family).to be_a(Family)
    end

    context 'when creating' do
      it 'sets the _type field correctly' do
        expect(application._type).to eq('IndividualMarket::Application')
      end

      it 'is an instance of IndividualMarket::Application' do
        application
        expect(Sbm::Application.first).to be_a(IndividualMarket::Application)
      end

      it 'is an instance of Sbm::Application' do
        application
        expect(Sbm::Application.first).to be_a(Sbm::Application)
      end
    end
  end

  describe 'fields' do
    it { is_expected.to have_field(:hbx_id).of_type(String) }
    it { is_expected.to have_field(:effective_on).of_type(Date) }
    it { is_expected.to have_field(:submitted_at).of_type(DateTime) }
    it { is_expected.to have_field(:family_updated_at).of_type(DateTime) }
    it { is_expected.to have_field(:assistance_year).of_type(Integer) }
    it { is_expected.to have_field(:predecessor_id).of_type(BSON::ObjectId) }
    it { is_expected.to have_field(:origin).of_type(Symbol) }
    it { is_expected.to have_field(:generation_reason).of_type(Symbol) }
  end

  describe 'validations' do
    describe '#no_duplicate_relationships' do
      let(:applicant1) { application.primary_applicant }
      let(:applicant2) { FactoryBot.build(:individual_market_applicant, :dependent) }
      let(:relationship1) { FactoryBot.build(:individual_market_relationship, source_id: applicant1.id, relative_id: applicant2.id, kind: 'spouse') }

      before do
        application.applicants = [applicant1, applicant2]
      end

      context 'when there are no duplicate relationships' do
        it 'is valid' do
          application.relationships = [relationship1]
          expect(application.valid?).to be true
        end
      end

      context 'when there are duplicate relationships' do
        let(:relationship2) { FactoryBot.build(:individual_market_relationship, source_id: applicant1.id, relative_id: applicant2.id, kind: 'child') }

        it 'is invalid' do
          application.relationships = [relationship1, relationship2]
          expect(application.valid?).to be false
        end

        it 'adds an error message' do
          application.relationships = [relationship1, relationship2]
          application.valid?
          expect(application.errors[:relationships]).to include('contains duplicate relationships (same source and relative)')
        end
      end

      context 'when relationships have different source and relative pairs' do
        let(:relationship2) { FactoryBot.build(:individual_market_relationship, source_id: applicant2.id, relative_id: applicant1.id, kind: 'parent') }

        it 'is valid' do
          application.relationships = [relationship1, relationship2]
          expect(application.valid?).to be true
        end
      end
    end

    describe 'enumeration fields' do
      shared_examples_for 'an enumeration field' do |field, valid_values|
        context 'when set to valid values' do
          valid_values.each do |value|
            it "is valid with :#{value}" do
              application.send("#{field}=", value)
              expect(application.valid?).to be true
            end
          end
        end

        context 'when set to invalid value' do
          it "is invalid with an unrecognized value" do
            application.send("#{field}=", :invalid_value)
            expect(application.valid?).to be false
            expect(application.errors[field]).to include('is not included in the list')
          end

          it "is invalid with nil" do
            application.send("#{field}=", nil)
            expect(application.valid?).to be false
            expect(application.errors[field]).to include('is not included in the list')
          end
        end
      end

      context 'origin validation' do
        it_behaves_like 'an enumeration field', :origin, %i[user system admin data_import migration]
      end

      context 'generation_reason validation' do
        it_behaves_like 'an enumeration field', :generation_reason, %i[manual rop_expiration renewal]
      end
    end

    describe 'assistance_year validation' do
      context 'when set to current year' do
        it 'returns true' do
          application.assistance_year = Date.today.year
          expect(application.valid?).to be true
        end
      end

      context 'when set to a year less than 2024' do
        it 'returns false' do
          application.assistance_year = 2023
          expect(application.valid?).to be false
          expect(application.errors[:assistance_year]).to include('must be greater than or equal to 2024')
        end
      end

      context 'when set to a year greater than 2024' do
        it 'returns true' do
          application.assistance_year = 2025
          expect(application.valid?).to be true
        end
      end

      context 'when set to nil' do
        it 'returns false' do
          application.assistance_year = nil
          expect(application.valid?).to be false
          expect(application.errors[:assistance_year]).to include("can't be blank")
        end
      end
    end
  end

  describe 'state machine' do
    let(:failure_comment) { {comment: 'Missing information'} }
    let(:reset_comment) { {comment: 'Fixing application'} }
    let(:expire_comment) { {comment: 'Application expired'} }

    context 'default state' do
      it 'has an initial state by default' do
        expect(application.current_state).to eq(:initial)
      end

      it 'has no state history records initially' do
        expect(application.state_histories.count).to eq(0)
      end
    end

    describe 'state transitions' do
      context 'from initial state' do
        let(:application) { FactoryBot.create(:individual_market_application, :initial) }

        it 'can transition to submission_failed' do
          expect(application.can_failed_submission?).to be true
          application.failed_submission(reason: 'Validation errors')
          expect(application.current_state).to eq(:submission_failed)
        end

        it 'can transition to submitted' do
          expect(application.can_submit?).to be true
          application.submit(reason: 'Application submitted')
          expect(application.current_state).to eq(:submitted)
        end

        it 'can transition to expired' do
          expect(application.can_expire?).to be true
          application.expire(**expire_comment)
          expect(application.current_state).to eq(:expired)
        end

        it 'can transition to cancelled' do
          expect(application.can_cancel?).to be true
          application.cancel(reason: 'Application cancelled')
          expect(application.current_state).to eq(:cancelled)
        end

        it 'cannot transition to determined or determination_failed' do
          expect(application.can_determine?).to be false
          expect(application.can_failed_determination?).to be false
          expect { application.determine }.to raise_error(RuntimeError)
          expect { application.failed_determination }.to raise_error(RuntimeError)
        end

        it 'cannot transition to initial (already there)' do
          expect(application.can_reset?).to be false
          expect { application.reset }.to raise_error(RuntimeError)
        end
      end

      context 'from submission_failed state' do
        let(:application) { FactoryBot.create(:individual_market_application, :submission_failed) }

        it 'can transition to initial via reset' do
          expect(application.can_reset?).to be true
          application.reset(reason: 'Resetting application')
          expect(application.current_state).to eq(:initial)
        end

        it 'can transition to submitted' do
          expect(application.can_submit?).to be true
          application.submit(reason: 'Re-submitting application')
          expect(application.current_state).to eq(:submitted)
        end

        it 'can transition to expired' do
          expect(application.can_expire?).to be true
          application.expire(**expire_comment)
          expect(application.current_state).to eq(:expired)
        end

        it 'can transition to cancelled' do
          expect(application.can_cancel?).to be true
          application.cancel(reason: 'Application cancelled')
          expect(application.current_state).to eq(:cancelled)
        end

        it 'cannot transition to determined or determination_failed' do
          expect(application.can_determine?).to be false
          expect(application.can_failed_determination?).to be false
        end

        it 'cannot transition to submission_failed (already there)' do
          expect(application.can_failed_submission?).to be false
          expect { application.failed_submission }.to raise_error(RuntimeError)
        end
      end

      context 'from submitted state' do
        let(:application) { FactoryBot.create(:individual_market_application, :submitted) }

        it 'can transition to determined' do
          expect(application.can_determine?).to be true
          application.determine(reason: 'Application determined')
          expect(application.current_state).to eq(:determined)
        end

        it 'can transition to determination_failed' do
          expect(application.can_failed_determination?).to be true
          application.failed_determination(reason: 'Determination failed')
          expect(application.current_state).to eq(:determination_failed)
        end

        it 'can transition to expired' do
          expect(application.can_expire?).to be true
          application.expire(**expire_comment)
          expect(application.current_state).to eq(:expired)
        end

        it 'can transition to cancelled' do
          expect(application.can_cancel?).to be true
          application.cancel(reason: 'Application cancelled')
          expect(application.current_state).to eq(:cancelled)
        end

        it 'cannot transition to initial or submission_failed' do
          expect(application.can_reset?).to be false
          expect(application.can_failed_submission?).to be false
        end

        it 'cannot transition to submitted (already there)' do
          expect(application.can_submit?).to be false
          expect { application.submit }.to raise_error(RuntimeError)
        end
      end

      context 'from determined state' do
        let(:application) { FactoryBot.create(:individual_market_application, :determined) }

        describe 'valid transitions' do
          it 'can transition to expired' do
            expect(application.can_expire?).to be true
            application.expire(**expire_comment)
            expect(application.current_state).to eq(:expired)
          end

          it 'can transition to family_sync_failed' do
            expect(application.can_failed_family_sync?).to be true
            application.failed_family_sync(reason: 'Family sync failed')
            expect(application.current_state).to eq(:family_sync_failed)
          end
        end

        describe 'invalid transitions' do
          it 'cannot transition to initial state' do
            expect(application.can_reset?).to be false
          end

          it 'cannot transition to submission_failed state' do
            expect(application.can_failed_submission?).to be false
          end

          it 'cannot transition to submitted state' do
            expect(application.can_submit?).to be false
          end

          it 'cannot transition to determination_failed state' do
            expect(application.can_failed_determination?).to be false
          end

          it 'cannot transition to determined state (already there)' do
            expect(application.can_determine?).to be false
          end

          it 'cannot transition to cancelled state' do
            expect(application.can_cancel?).to be false
          end
        end
      end

      context 'from determination_failed state' do
        let(:application) { FactoryBot.create(:individual_market_application, :determination_failed) }

        it 'can transition to expired' do
          expect(application.can_expire?).to be true
          application.expire(**expire_comment)
          expect(application.current_state).to eq(:expired)
        end

        it 'can transition to cancelled' do
          expect(application.can_cancel?).to be true
          application.cancel(reason: 'Application cancelled')
          expect(application.current_state).to eq(:cancelled)
        end

        it 'cannot transition to other states' do
          expect(application.can_reset?).to be false
          expect(application.can_failed_submission?).to be false
          expect(application.can_submit?).to be false
          expect(application.can_failed_determination?).to be false
          expect(application.can_determine?).to be false
          expect(application.can_failed_family_sync?).to be false
        end
      end

      context 'from expired state' do
        let(:application) { FactoryBot.create(:individual_market_application, :expired) }

        it 'cannot transition to any other state' do
          expect(application.can_reset?).to be false
          expect(application.can_failed_submission?).to be false
          expect(application.can_submit?).to be false
          expect(application.can_failed_determination?).to be false
          expect(application.can_determine?).to be false
          expect(application.can_expire?).to be false
          expect(application.can_cancel?).to be false
          expect(application.can_failed_family_sync?).to be false
        end
      end

      context 'from cancelled state' do
        let(:application) { FactoryBot.create(:individual_market_application, :cancelled) }

        it 'cannot transition to any other state' do
          expect(application.can_reset?).to be false
          expect(application.can_failed_submission?).to be false
          expect(application.can_submit?).to be false
          expect(application.can_failed_determination?).to be false
          expect(application.can_determine?).to be false
          expect(application.can_expire?).to be false
          expect(application.can_cancel?).to be false
          expect(application.can_failed_family_sync?).to be false
        end
      end

      context 'from family_sync_failed state' do
        let(:application) { FactoryBot.create(:individual_market_application, :family_sync_failed) }

        it 'cannot transition to any other state' do
          expect(application.can_reset?).to be false
          expect(application.can_failed_submission?).to be false
          expect(application.can_submit?).to be false
          expect(application.can_failed_determination?).to be false
          expect(application.can_determine?).to be false
          expect(application.can_expire?).to be false
          expect(application.can_cancel?).to be false
          expect(application.can_failed_family_sync?).to be false
        end
      end
    end

    describe 'state history tracking' do
      let(:state_history) { application.state_histories.first }

      before :each do
        application.submit(**comment1, **reason1)
        application.save!
        application.reload
      end

      context 'when comment and reason are provided' do
        let(:comment1) { {comment: 'Completed application'} }
        let(:reason1) { {reason: 'COMPLETE'} }

        it 'persists from state' do
          expect(state_history.from_state).to eq(:initial)
        end

        it 'persists to state' do
          expect(state_history.to_state).to eq(:submitted)
        end

        it 'persists event' do
          expect(state_history.event).to eq(:submit)
        end

        it 'persists comment' do
          expect(state_history.comment).to eq('Completed application')
        end

        it 'persists reason code' do
          expect(state_history.reason).to eq('COMPLETE')
        end

        it 'persists effective_on' do
          expect(state_history.effective_on).not_to be_nil
        end
      end

      context 'when comment and reason are not provided' do
        let(:comment1) { {comment: nil } }
        let(:reason1) { {reason: nil } }

        it 'persists nil comment' do
          expect(state_history.comment).to be_nil
        end

        it 'persists nil reason' do
          expect(state_history.reason).to be_nil
        end
      end
    end

    describe 'error handling' do
      it 'raises error when transitioning from an invalid state' do
        application.current_state = :invalid_state

        expect { application.submit }.to raise_error(RuntimeError, /Invalid transition from invalid_state/)
      end

      it 'raises error when attempting an invalid transition' do
        application.submit # Move to submitted state

        expect { application.submit }.to raise_error(RuntimeError, /Invalid transition from submitted/)
      end
    end
  end

  describe '#only_one_primary_applicant' do
    let(:primary_applicant) { FactoryBot.build(:individual_market_applicant, is_primary_applicant: true) }
    let(:dependent_applicant) { FactoryBot.build(:individual_market_applicant, :dependent) }
    let(:another_primary_applicant) { FactoryBot.build(:individual_market_applicant, is_primary_applicant: true) }

    context 'without primary applicant' do
      before do
        application.applicants = [dependent_applicant]
      end

      it 'is invalid' do
        expect(application.valid?).to be false
        expect(application.errors[:applicants]).to include('must have exactly one primary applicant')
      end
    end

    context 'with multiple primary applicants' do
      before do
        application.applicants = [primary_applicant, another_primary_applicant]
      end

      it 'is invalid' do
        expect(application.valid?).to be false
        expect(application.errors[:applicants]).to include('must have exactly one primary applicant')
      end
    end

    context 'with one primary applicant' do
      before do
        application.applicants = [primary_applicant, dependent_applicant]
      end

      it 'is valid' do
        expect(application.valid?).to be true
      end
    end
  end

  context 'newest_determined_by_family_id' do
    let(:family_id) { application.family.id }
    let!(:current_application_1) do
      FactoryBot.create(
        :individual_market_application,
        :determined,
        family: application.family,
        submitted_at: TimeKeeper.date_of_record - 1.month,
        created_at: TimeKeeper.date_of_record + 1.year
      )
    end
    let!(:current_application_2) do
      FactoryBot.create(
        :individual_market_application,
        :determined,
        family: application.family,
        submitted_at: TimeKeeper.date_of_record - 2.month
      )
    end

    it 'should return only the most recently submitted determined application with the greatest assistance year' do
      application = IndividualMarket::Application.newest_determined_by_family_id(family_id).first
      expect(application).to eq current_application_1
    end
  end

  context 'for_determined_family' do
    let(:family_id) { application.family.id }
    let!(:determined_application) do
      FactoryBot.create(
        :individual_market_application,
        :determined,
        family: application.family,
        submitted_at: TimeKeeper.date_of_record - 1.month,
        created_at: TimeKeeper.date_of_record + 1.year
      )
    end

    let!(:submitted_application) do
      FactoryBot.create(
        :individual_market_application,
        :submitted,
        family: application.family,
        submitted_at: TimeKeeper.date_of_record - 1.month,
        created_at: TimeKeeper.date_of_record + 1.year
      )
    end

    it 'should return only determined applications' do
      applications = IndividualMarket::Application.for_determined_family(family_id)
      expect(applications.map(&:current_state)).to include :determined
    end

    it 'should not return any submitted applications' do
      expect(IndividualMarket::Application.for_determined_family(family_id).to_a).to include(determined_application)
      expect(IndividualMarket::Application.for_determined_family(family_id).to_a).not_to include(submitted_application)
    end
  end

  describe '#assign_hbx_id' do
    context 'when hbx_id is not set' do
      it 'assigns a new hbx_id' do
        expect(application.hbx_id).to be_present
      end
    end

    context 'when hbx_id is already set' do
      let(:hbx_id) { '83839273639289363' }
      let(:application) { FactoryBot.create(:individual_market_application, :with_primary, hbx_id: hbx_id) }

      it 'does not update hbx_id' do
        expect(application.hbx_id).to eq(hbx_id)
      end
    end
  end

  describe 'index: unique hbx_id' do
    let(:application1) { FactoryBot.create(:individual_market_application, :with_primary) }
    let(:application2) { FactoryBot.create(:individual_market_application, :with_primary, hbx_id: hbx_id2) }
    let(:hbx_id1) { application1.hbx_id }

    before :each do
      application1
      described_class.remove_indexes
      described_class.create_indexes
    end

    context 'when hbx_id is unique' do
      let(:hbx_id2) { '3868646846578468765478' }

      it 'creates second application without raising an error' do
        expect { application2 }.not_to raise_error
      end
    end

    context 'when hbx_id is not unique' do
      let(:hbx_id2) { hbx_id1 }

      it 'raises a Mongo::Error::OperationFailure error' do
        expect { application2 }.to raise_error(
          Mongo::Error::OperationFailure
        ).with_message(
          /E11000 duplicate key error collection/
        )
      end
    end
  end

  describe '#build_attestation' do
    let(:application) { FactoryBot.create(:individual_market_application, :with_primary) }
    let(:person) { FactoryBot.create(:person, :with_hbx_staff_role) }
    let(:user) { FactoryBot.create(:user, person: person) }
    let(:attested) { true }
    let(:given_name) { 'Johnny' }
    let(:family_name) { 'Doe' }
    let(:family) { application.family }

    it 'builds an attestation with the correct signer role' do
      application.build_attestation(attested, given_name, family_name, user)
      expect(application.attestation).to be_present
      expect(application.attestation.signed_at).to be_present
      expect(application.attestation.signer_id).to eq(user.id)
      expect(application.attestation.signer_role).to eq("admin")
    end

    it 'does not build an attestation if the given name is not valid' do
      application.build_attestation(attested, "charles", family_name, user)
      expect(application.attestation).to be_nil
    end

    it 'does not build an attestation if the family name is not valid' do
      application.build_attestation(attested, given_name, "smith", user)
      expect(application.attestation).to be_nil
    end

    it 'does not build an attestation if it is not attested' do
      application.build_attestation(false, given_name, family_name, user)
      expect(application.attestation).to be_nil
    end

    it 'does not set the signer_id if the signer is not a user' do
      application.build_attestation(attested, given_name, family_name)
      expect(application.attestation).to be_present
      expect(application.attestation.signer_id).to be_nil
    end

    it 'sets the signer_role to consumer if the applicant person is the user' do
      application.applicants.first.family_member.person = user.person
      application.build_attestation(attested, given_name, family_name, user)
      expect(application.attestation).to be_present
      expect(application.attestation.signer_role).to eq("consumer")
    end

    context 'broker agent' do
      let(:broker_person) { FactoryBot.create(:person) }
      let(:broker_agency_profile) { FactoryBot.create(:benefit_sponsors_organizations_broker_agency_profile) }
      let(:broker_role) { FactoryBot.create(:broker_role, aasm_state: 'active', benefit_sponsors_broker_agency_profile_id: broker_agency_profile.id, person: broker_person) }
      let(:broker_agency_account) { FactoryBot.create(:benefit_sponsors_accounts_broker_agency_account, broker_agency_profile: broker_agency_profile, writing_agent_id: broker_role.id, is_active: true) }
      let(:broker_user) { FactoryBot.create(:user, person: broker_person) }

      before do
        allow(family).to receive(:active_broker_agency_account).and_return broker_agency_account
      end

      it 'sets the signer_role to broker if the writing agent is the user' do
        application.build_attestation(attested, given_name, family_name, broker_user)
        expect(application.attestation).to be_present
        expect(application.attestation.signer_role).to eq("broker")
      end
    end

    context 'assister agent' do
      let(:assister_person) { FactoryBot.create(:person) }
      let(:assister_agency_profile) { FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile) }
      let(:assister_role) { FactoryBot.create(:assister_role, aasm_state: 'active', benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id, person: assister_person) }
      let(:assister_agency_account) { FactoryBot.create(:benefit_sponsors_accounts_assister_agency_account, assister_agency_profile: assister_agency_profile, writing_agent_id: assister_role.id, is_active: true) }
      let(:assister_user) { FactoryBot.create(:user, person: assister_person) }

      before do
        allow(family).to receive(:active_assister_agency_account).and_return assister_agency_account
      end

      it 'sets the signer_role to assister if the writing agent is the user' do
        application.build_attestation(attested, given_name, family_name, assister_user)
        expect(application.attestation).to be_present
        expect(application.attestation.signer_role).to eq("assister")
      end
    end

    context 'broker agency staff' do
      let(:market_kind) { :individual }
      let(:broker_person) { FactoryBot.create(:person) }
      let(:broker_role) { FactoryBot.create(:broker_role, person: broker_person) }
      let(:broker_staff_person) { FactoryBot.create(:person) }
      let(:broker_staff_state) { 'active' }
      let(:broker_staff) do
        FactoryBot.create(
          :broker_agency_staff_role,
          person: broker_staff_person,
          aasm_state: broker_staff_state,
          benefit_sponsors_broker_agency_profile_id: broker_agency_id
        )
      end

      let(:site) do
        FactoryBot.create(
          :benefit_sponsors_site,
          :with_benefit_market,
          :as_hbx_profile,
          site_key: ::EnrollRegistry[:enroll_app].settings(:site_key).item
        )
      end

      let(:broker_agency_organization) { FactoryBot.create(:benefit_sponsors_organizations_general_organization, :with_broker_agency_profile, site: site) }
      let(:broker_agency_profile) { broker_agency_organization.broker_agency_profile }
      let(:broker_agency_id) { broker_agency_profile.id }
      let(:baa_active) { true }
      let(:broker_staff_user) { FactoryBot.create(:user, person: broker_staff_person) }
      let(:broker_agency_account) do
        family.broker_agency_accounts.create!(
          benefit_sponsors_broker_agency_profile_id: broker_agency_id,
          writing_agent_id: broker_role.id,
          is_active: baa_active,
          start_on: TimeKeeper.date_of_record
        )
      end

      before do
        broker_role.update_attributes!(benefit_sponsors_broker_agency_profile_id: broker_agency_id)
        broker_person.create_broker_agency_staff_role(
          benefit_sponsors_broker_agency_profile_id: broker_role.benefit_sponsors_broker_agency_profile_id
        )
        broker_agency_profile.update_attributes!(primary_broker_role_id: broker_role.id, market_kind: market_kind)
        broker_role.approve!
        broker_agency_account
        broker_staff
      end

      it 'sets the signer_role to broker_staff' do
        application.build_attestation(attested, given_name, family_name, broker_staff_user)
        expect(application.attestation).to be_present
        expect(application.attestation.signer_role).to eq('broker_staff')
      end
    end
  end

  describe '#set_submit' do
    let(:application) { FactoryBot.create(:individual_market_application, :with_primary, effective_on: nil) }

    before do
      application.set_submit
    end

    it 'assigns the submitted_at timestamp' do
      expect(application.submitted_at).to be_present
    end

    it 'assigns effective_on based on the assistance year' do
      expect(application.effective_on).to be_present
    end
  end

  describe '#fetch_evidence' do
    let(:application) { FactoryBot.create(:individual_market_application, :with_primary) }
    let(:applicant) { application.primary_applicant }
    let(:family_member) { application.family.family_members.first }
    let(:ivl_eligibility) { applicant.individual_market_eligibility }
    let(:alive_evidence) { FactoryBot.create(:alive_evidence, :pending, eligibility: ivl_eligibility) }
    let(:ai_an_evidence) { FactoryBot.create(:american_indian_evidence, :with_verification_histories, :verified, eligibility: ivl_eligibility) }

    before do
      alive_evidence
      ai_an_evidence
    end

    it 'returns the evidence' do
      expect(application.fetch_evidence(alive_evidence.id, family_member.id)).to eq(alive_evidence)
    end

    it 'does not return the evidence if the id does not match' do
      expect(application.fetch_evidence(alive_evidence.id, family_member.id)).not_to eq(ai_an_evidence)
    end

    it 'does not return the evidence if the family member id does not match' do
      expect(application.fetch_evidence(alive_evidence.id, BSON::ObjectId.new)).to be_nil
    end
  end

  describe '#applicants_by_hbx_ids' do
    let(:application) { FactoryBot.create(:individual_market_application, :with_primary) }
    let(:applicant1) { application.primary_applicant }
    let!(:applicant2) { FactoryBot.create(:individual_market_applicant, application: application, hbx_id: 'qhp_67890') }
    let!(:applicant3) { FactoryBot.create(:individual_market_applicant, application: application, hbx_id: 'qhp_11111') }

    context 'when provided with matching hbx_ids' do
      it 'returns applicants with matching hbx_ids' do
        result = application.applicants_by_hbx_ids(['qhp_11111', 'qhp_67890'])
        expect(result.count).to eq(2)
        expect(result.pluck(:hbx_id)).to match_array(['qhp_11111', 'qhp_67890'])
      end
    end

    context 'when provided with non-matching hbx_ids' do
      it 'returns an empty collection' do
        result = application.applicants_by_hbx_ids(['qhp_99999', 'qhp_88888'])
        expect(result).to be_empty
      end
    end

    context 'when provided with empty array' do
      it 'returns an empty collection' do
        result = application.applicants_by_hbx_ids([])
        expect(result).to be_empty
      end
    end
  end
end
