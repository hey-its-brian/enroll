# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Handlers::FAApplication::MigrateEvidence, dbclean: :after_each do
  include Dry::Monads[:do, :result]

  before :all do
    DatabaseCleaner.clean
  end

  let!(:family) { FactoryBot.create(:family, :with_primary_family_member_and_dependent)}
  let!(:person) { family.primary_person }
  let!(:person2) { FactoryBot.create(:person, hbx_id: '1234567890') }
  let!(:family_member) do
    FactoryBot.create(:family_member,
                      family: family,
                      person: person2,
                      is_active: true,
                      is_primary_applicant: false)
  end
  let!(:application) do
    FactoryBot.create(:application,
                      family_id: family.id,
                      aasm_state: "determined",
                      effective_date: (TimeKeeper.date_of_record - 12.days))
  end

  let!(:applicant) do
    FactoryBot.create(:applicant,
                      application: application,
                      dob: TimeKeeper.date_of_record - 40.years,
                      is_primary_applicant: true,
                      family_member_id: family.family_members[0].id,
                      person_hbx_id: person.hbx_id,
                      addresses: [FactoryBot.build(:financial_assistance_address)])
  end

  let!(:applicant2) do
    FactoryBot.create(:applicant,
                      application: application,
                      dob: TimeKeeper.date_of_record - 40.years,
                      is_primary_applicant: false,
                      family_member_id: family.family_members[1].id,
                      person_hbx_id: person2.hbx_id,
                      addresses: [FactoryBot.build(:financial_assistance_address)])
  end

  describe 'migrate evidences' do
    let!(:income_evidence) do
      applicant.create_income_evidence(key: :income,
                                       title: 'Income',
                                       aasm_state: 'outstanding',
                                       due_on: TimeKeeper.date_of_record + 30.days,
                                       verification_outstanding: true,
                                       is_satisfied: false,
                                       external_service: 'FDSH IFSV',
                                       updated_by: "admin",
                                       description: 'Income')
    end

    let!(:esi_evidence) do
      applicant.create_esi_evidence(key: :esi_mec,
                                    title: 'ESI MEC',
                                    aasm_state: 'verified',
                                    due_on: TimeKeeper.date_of_record + 30.days,
                                    verification_outstanding: true,
                                    is_satisfied: false,
                                    external_service: 'FDSH IFSV',
                                    updated_by: "admin",
                                    description: 'ESI MEC')
    end

    let!(:income_evidence2) do
      applicant2.create_income_evidence(key: :income,
                                        title: 'Income',
                                        aasm_state: 'unverified',
                                        due_on: TimeKeeper.date_of_record + 30.days,
                                        verification_outstanding: true,
                                        is_satisfied: false,
                                        external_service: 'FDSH IFSV',
                                        updated_by: "admin",
                                        description: 'Income')
    end

    let!(:esi_evidence2) do
      applicant2.create_esi_evidence(key: :esi_mec,
                                     title: 'ESI MEC',
                                     aasm_state: 'rejected',
                                     due_on: TimeKeeper.date_of_record + 30.days,
                                     verification_outstanding: true,
                                     is_satisfied: false,
                                     external_service: 'FDSH IFSV',
                                     updated_by: "admin",
                                     description: 'ESI MEC')
    end

    let!(:document) do
      income_evidence.documents.create(title: 'document.pdf', creator: 'mehl', subject: 'document.pdf', publisher: 'mehl', type: 'text', identifier: 'identifier', source: 'enroll_system', language: 'en')
    end

    let!(:verification_history) do
      income_evidence.verification_histories.create!(
        action: 'hub request',
        modifier: 'demographic',
        update_reason: 'demographic',
        updated_by: 'user@user.com',
        is_satisfied: false,
        verification_outstanding: true,
        due_on: TimeKeeper.date_of_record + 35.days,
        date_of_action: TimeKeeper.date_of_record - 35.days
      )

      income_evidence.verification_histories.create!(
        action: 'verify',
        modifier: 'admin',
        update_reason: 'Document in EnrollApp',
        updated_by: 'admin@user.com',
        is_satisfied: true,
        verification_outstanding: false,
        due_on: nil,
        date_of_action: TimeKeeper.date_of_record - 40.days
      )

      income_evidence.verification_histories.create!(
        action: 'hub request',
        modifier: 'admin',
        update_reason: 'hub call',
        updated_by: 'admin@user.com',
        is_satisfied: false,
        verification_outstanding: true,
        due_on: TimeKeeper.date_of_record + 30.days,
        date_of_action: TimeKeeper.date_of_record - 30.days
      )
    end

    let!(:request_results) do
      income_evidence.request_results.create!(
        result: 'outstanding',
        source: 'FDSH',
        source_transaction_id: '1234567890',
        code: '123',
        code_description: 'Code description',
        raw_payload: 'raw_payload',
        action: 'hub response'
      )
    end

    let!(:workflow_state_transition) do
      income_evidence.workflow_state_transitions.create!(
        to_state: 'unverified',
        from_state: 'unverified',
        transition_at: TimeKeeper.date_of_record - 35.days,
        event: 'move_to_unverified',
        reason: 'verification_requested move_to_unverified',
        comment: 'comment move_to_unverified'
      )

      income_evidence.workflow_state_transitions.create!(
        to_state: 'verified',
        from_state: 'unverified',
        transition_at: TimeKeeper.date_of_record - 40.days,
        event: 'move_to_verified',
        reason: 'verified',
        comment: 'verified'
      )

      income_evidence.workflow_state_transitions.create!(
        to_state: 'outstanding',
        from_state: 'verified',
        transition_at: TimeKeeper.date_of_record - 30.days,
        event: 'move_to_outstanding',
        reason: 'verification_requested',
        comment: 'comment'
      )
    end

    context '#perform' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
        @result = subject.call({document_id: application.id.to_s})
        application.reload
        @old_income_evidence = application.applicants.first.income_evidence
        @new_income_evidence = application.applicants.first.aptc_csr_eligibility.evidences.first
      end

      it 'should be a success' do
        expect(@result).to be_success
        expect(@result.value!).to be_a(Array)
        expect(@result.value!.count).to eq(4)
      end

      it 'should create aptc csr eligibility' do
        aptc_csr_eligibility = application.applicants.first.aptc_csr_eligibility
        expect(aptc_csr_eligibility).to be_present
        expect(aptc_csr_eligibility.evidences.count).to eq(2)
        expect(aptc_csr_eligibility.created_at).to be_present
        expect(aptc_csr_eligibility.updated_at).to be_present
        expect(aptc_csr_eligibility.current_state).to eq(:verification_in_progress)
        expect(aptc_csr_eligibility.is_satisfied).to eq(false)
        expect(aptc_csr_eligibility._type).to eq('Eligibilities::V3::AptcCsrEligibility')
        expect(aptc_csr_eligibility.determined_at).to be_present
        expect(aptc_csr_eligibility.state_histories.count).to eq(1)
        expect(aptc_csr_eligibility.state_histories.first.to_state).to eq(:verification_in_progress)
        expect(aptc_csr_eligibility.state_histories.first.from_state).to eq(:initial)
        expect(aptc_csr_eligibility.state_histories.first.transition_at).to be_present
        expect(aptc_csr_eligibility.state_histories.first.event).to eq(:pend)
        expect(aptc_csr_eligibility.state_histories.first.reason).to eq("migrating from the application #{application.hbx_id} to create aptc_csr_eligibility")
      end

      it 'should migrate evidence 1.0 to 3.0' do
        expect(@new_income_evidence.id).not_to eq(@old_income_evidence.id)
        expect(@new_income_evidence.created_at).to be_present
        expect(@new_income_evidence.updated_at).to be_present
        expect(@new_income_evidence.key.to_s).to eq("#{@old_income_evidence.key}_evidence")
        expect(@new_income_evidence.title).to eq("#{@old_income_evidence.title} Evidence")
        expect(@new_income_evidence._type).to eq('FinancialAssistance::Evidences::IncomeEvidence')
        expect(@new_income_evidence.current_state.to_s).to eq(@old_income_evidence.aasm_state.to_s)
        expect(@new_income_evidence.verification_outstanding).to eq(@old_income_evidence.verification_outstanding)
        expect(@new_income_evidence.due_on).to eq(@old_income_evidence.due_on)
        expect(@new_income_evidence.is_satisfied).to eq(@old_income_evidence.is_satisfied)
        expect(@new_income_evidence.updated_by).to eq(@old_income_evidence.updated_by)
        expect(@new_income_evidence.external_service).to eq(@old_income_evidence.external_service)
        expect(@new_income_evidence.determined_at).to eq(@old_income_evidence.request_results.first.date_of_action)
        expect(@new_income_evidence.verification_histories.count).to eq(@old_income_evidence.verification_histories.count)
      end

      it 'should migrate verification history 1.0 to 3.0' do
        old_verification_histories = @old_income_evidence.verification_histories.order_by(:date_of_action.asc)
        new_verification_histories = @new_income_evidence.verification_histories.order_by(:date_of_action.asc)
        expect(new_verification_histories.count).to eq(old_verification_histories.count)
        expect(new_verification_histories.map(&:action)).to eq(old_verification_histories.map(&:action))
        new_verification_history = new_verification_histories.last
        old_verification_history = old_verification_histories.last
        expect(new_verification_history.created_at).to be_present
        expect(new_verification_history.updated_at).to be_present
        expect(new_verification_history.id).not_to eq(old_verification_history.id)
        expect_attributes_to_match(new_verification_history, old_verification_history, [:action, :update_reason, :updated_by, :is_satisfied, :verification_outstanding, :due_on, :date_of_action])
      end

      it 'should migrate request result 1.0 to 3.0' do
        old_request_results = @old_income_evidence.request_results.order_by(:date_of_action.asc)
        new_request_results = @new_income_evidence.request_results.order_by(:date_of_action.asc)
        expect(new_request_results.count).to eq(old_request_results.count)
        new_request_result = new_request_results.last
        old_request_result = old_request_results.last
        expect(new_request_result.created_at).to be_present
        expect(new_request_result.updated_at).to be_present
        expect(new_request_result.id).not_to eq(old_request_result.id)
        expect_attributes_to_match(new_request_result, old_request_result, [:result, :source, :source_transaction_id, :code, :code_description, :raw_payload, :action, :date_of_action])
      end

      it 'should migrate workflow state transition 1.0 to 3.0' do
        old_state_transitions = @old_income_evidence.workflow_state_transitions.order_by(:transition_at.asc)
        new_state_transitions = @new_income_evidence.state_histories.order_by(:transition_at.asc)
        expect(new_state_transitions.count).to eq(old_state_transitions.count)
        expect(new_state_transitions.map(&:to_state)).to eq(old_state_transitions.map(&:to_state).map(&:to_sym))
        new_state_transition = new_state_transitions.last
        old_state_transition = old_state_transitions.last
        expect(new_state_transition.created_at).to be_present
        expect(new_state_transition.updated_at).to be_present
        expect(new_state_transition.id).not_to eq(old_state_transition.id)
        expect(new_state_transition.to_state.to_s).to eq(old_state_transition.to_state.to_s)
        expect(new_state_transition.from_state.to_s).to eq(old_state_transition.from_state.to_s)
        expect(new_state_transition.transition_at).to eq(old_state_transition.transition_at)
        expect(new_state_transition.event.to_s).to eq(old_state_transition.event.to_s)
        expect(new_state_transition.reason).to eq(old_state_transition.reason)
        expect(new_state_transition.effective_on).to eq(old_state_transition.transition_at)
        expect(new_state_transition.is_eligible).to eq false
        expect(new_state_transition.metadata).to eq(old_state_transition.metadata)
      end

      it 'should migrate evidence documents from 1.0 to 3.0' do
        old_income_evidence_documents = @old_income_evidence.documents
        new_income_evidence_documents = @new_income_evidence.documents
        expect(new_income_evidence_documents.count).to eq(old_income_evidence_documents.count)
        new_income_evidence_document = new_income_evidence_documents.first
        old_income_evidence_document = old_income_evidence_documents.first
        expect(new_income_evidence_document.created_at).to be_present
        expect(new_income_evidence_document.updated_at).to be_present
        expect(new_income_evidence_document.id).not_to eq(old_income_evidence_document.id)
        expect_attributes_to_match(new_income_evidence_document, old_income_evidence_document, [:title, :creator, :subject, :publisher, :type, :identifier, :source, :language])
      end
    end

    context 'applicant is invalid' do
      before do
        applicant.addresses.update_all(county: nil, state: nil, kind: nil)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_county).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
        @result = subject.call({document_id: application.id.to_s})
        application.reload
      end

      it 'should be a success' do
        expect(@result).to be_success
        expect(@result.value!).to be_a(Array)
        expect(@result.value!).to eq([[application.hbx_id, application.aasm_state, "not migrated", "Applicants is invalid"]])
        expect(application.applicants.first.aptc_csr_eligibility.present?).to be_falsey
      end
    end
  end

  describe 'imported application with no evidences' do
    before do
      application.update_attributes!(aasm_state: 'imported')
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      @result = subject.call({document_id: application.id.to_s})
      application.reload
    end

    it 'should be a success' do
      expect(@result).to be_success
      expect(@result.value!).to be_a(Array)
      expect(@result.value!).to eq([[application.hbx_id, application.aasm_state, "no evidences found", ""]])
      expect(application.applicants.first.aptc_csr_eligibility.present?).to be_falsey
    end
  end

  describe 'draft application with no evidences' do
    before do
      application.update_attributes!(aasm_state: 'draft')
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      @result = subject.call({document_id: application.id.to_s})
      application.reload
    end

    it 'should be a success' do
      expect(@result).to be_success
      expect(@result.value!).to be_a(Array)
      expect(@result.value!).to eq([[application.hbx_id, application.aasm_state, "no evidences found", ""]])
      expect(application.applicants.first.aptc_csr_eligibility.present?).to be_falsey
    end
  end
end

def expect_attributes_to_match(new_object, old_object, attributes)
  attributes.each do |attribute|
    expect(new_object.send(attribute)).to eq(old_object.send(attribute))
  end
end