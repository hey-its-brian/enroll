# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Handlers::FAApplication::FetchApplicationsWithoutV3Evidences, dbclean: :after_each do
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

  describe 'fetch application without eligibilities' do
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

    describe 'requested array' do
      context '#when there is only one application' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
          @result = subject.call({additional_params: { aasm_states: ['determined'], data_type: 'Array' }})
        end

        it 'should return the correct count' do
          expect(@result.count).to eq(1)
          expect(@result).to be_an(Array)
          expect(@result.first).to eq(application.id)
        end
      end

      context '#when there are multiple applications' do
        let!(:family2) { FactoryBot.create(:family, :with_primary_family_member_and_dependent)}
        let!(:person3) { family2.primary_person }
        let!(:person4) { FactoryBot.create(:person, hbx_id: '589452') }
        let!(:family_member4) do
          FactoryBot.create(:family_member,
                            family: family2,
                            person: person4,
                            is_active: true,
                            is_primary_applicant: false)
        end
        let!(:application2) do
          FactoryBot.create(:application,
                            family_id: family2.id,
                            aasm_state: "draft",
                            effective_date: (TimeKeeper.date_of_record - 12.days))
        end

        let!(:applicant3) do
          FactoryBot.create(:applicant,
                            application: application2,
                            dob: TimeKeeper.date_of_record - 40.years,
                            is_primary_applicant: true,
                            family_member_id: family2.family_members[0].id,
                            person_hbx_id: person3.hbx_id,
                            addresses: [FactoryBot.build(:financial_assistance_address)])
        end

        let!(:applicant4) do
          FactoryBot.create(:applicant,
                            application: application2,
                            dob: TimeKeeper.date_of_record - 40.years,
                            is_primary_applicant: false,
                            family_member_id: family2.family_members[1].id,
                            person_hbx_id: person4.hbx_id,
                            addresses: [FactoryBot.build(:financial_assistance_address)])
        end

        context 'and one with draft' do
          before do
            allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
            @result = subject.call({additional_params: { aasm_states: ['determined'], data_type: 'Array' }})
          end

          it 'should return the correct count' do
            expect(@result.count).to eq(1)
            expect(@result).to be_an(Array)
            expect(@result.first).to eq(application.id)
          end
        end
      end

      context "when application already have v3 evidence" do
        let!(:application_with_v3_evidence) do
          FactoryBot.create(:application,
                            family_id: family.id,
                            aasm_state: "determined",
                            effective_date: (TimeKeeper.date_of_record - 12.days))
        end

        let!(:applicant_with_v3_evidence) do
          FactoryBot.create(:applicant,
                            application: application_with_v3_evidence,
                            dob: TimeKeeper.date_of_record - 40.years,
                            is_primary_applicant: true,
                            family_member_id: family.family_members[0].id,
                            person_hbx_id: person.hbx_id,
                            addresses: [FactoryBot.build(:financial_assistance_address)])
        end

        let!(:aptc_csr_eligibility)  do
          eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: applicant_with_v3_evidence)
          old_state = FactoryBot.build(:v3_state_history, created_at: 2.days.ago)
          new_state = FactoryBot.build(:v3_state_history, created_at: 1.day.ago)
          eligibility.state_histories << old_state
          eligibility.state_histories << new_state
          eligibility.save!
          eligibility
        end

        let(:evidence) do
          FactoryBot.create(:income_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::IncomeEvidence',key: :income_evidence, title: 'Income Evidence', determined_at: TimeKeeper.date_of_record,
                                              description: 'Income Evidence Description', current_state: :pending)
        end
        let!(:old_state_history) { FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 2.days.ago) }
        let!(:new_state_history) { FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 1.day.ago) }
        let!(:v3_verification_history)  { FactoryBot.create(:v3_verification_history, evidence: evidence) }
        let!(:v3_request_result)  { FactoryBot.create(:v3_request_result, evidence: evidence) }

        let!(:document) do
          evidence.documents.create(title: 'document.pdf', creator: 'mehl', subject: 'document.pdf', publisher: 'mehl', type: 'text', identifier: 'identifier', source: 'enroll_system', language: 'en')
        end

        it 'should not return application with v3 evidence' do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
          result = subject.call({additional_params: { aasm_states: ['determined'], data_type: 'Array' }})
          expect(result).not_to include(application_with_v3_evidence.id)
        end
      end

      context "when applicant eligibilities is empty array" do
        let!(:application_with_v3_evidence) do
          FactoryBot.create(:application,
                            family_id: family.id,
                            aasm_state: "determined",
                            effective_date: (TimeKeeper.date_of_record - 12.days))
        end

        let!(:applicant_with_v3_evidence) do
          FactoryBot.create(:applicant,
                            application: application_with_v3_evidence,
                            dob: TimeKeeper.date_of_record - 40.years,
                            is_primary_applicant: true,
                            family_member_id: family.family_members[0].id,
                            person_hbx_id: person.hbx_id,
                            addresses: [FactoryBot.build(:financial_assistance_address)])
        end

        let!(:aptc_csr_eligibility)  do
          eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: applicant_with_v3_evidence)
          old_state = FactoryBot.build(:v3_state_history, created_at: 2.days.ago)
          new_state = FactoryBot.build(:v3_state_history, created_at: 1.day.ago)
          eligibility.state_histories << old_state
          eligibility.state_histories << new_state
          eligibility.save!
          eligibility
        end


        it 'should not return application with v3 evidence' do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
          applicant_with_v3_evidence.eligibilities.delete_all
          application_with_v3_evidence.save!
          result = subject.call({additional_params: { aasm_states: ['determined'], data_type: 'Array' }})
          expect(result).not_to include(application_with_v3_evidence.id)
        end
      end

      context "when params has invalid aasm_state" do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
          @result = subject.call({additional_params: { aasm_states: ['invalid_state'], data_type: 'Array' }})
        end

        it 'should return empty array' do
          expect(@result.failure).to eq("Invalid aasm_states provided")
        end
      end
    end
  end
end
