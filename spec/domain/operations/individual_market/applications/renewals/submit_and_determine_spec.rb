# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::Applications::Renewals::SubmitAndDetermine, dbclean: :after_each do

  let(:person) { FactoryBot.create(:person, :with_ssn, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }

  let(:renewal_application) { FactoryBot.create(:individual_market_application, :initial, :renewal, family_id: family.id) }
  let(:renewal_applicant) { FactoryBot.create(:individual_market_applicant, :with_person_name, application: renewal_application, family_member_id: primary_applicant.id) }
  let(:renewal_demographics) do
    demo = FactoryBot.create(:individual_market_demographics, applicant: renewal_applicant)
    renewal_applicant.build_individual_market_eligibility
    renewal_applicant.build_individual_market_evidences
    renewal_applicant.build_aptc_csr_eligibility
    renewal_applicant.save!
    demo
  end

  let(:result) { subject.call(application_id: renewal_demographics.applicant.application.id) }

  describe '#call' do
    context 'when:
      - renewal application exists in initial state
      - current application is IndividualMarket Application
      ' do

      let(:current_application) do
        application = FactoryBot.create(:individual_market_application, :determined, family_id: family.id)
        applicant = FactoryBot.create(:individual_market_applicant, :with_person_name, application: application, family_member_id: primary_applicant.id)
        FactoryBot.create(:individual_market_demographics, applicant: applicant)
        applicant.build_individual_market_eligibility
        applicant.build_individual_market_evidences
        applicant.individual_market_eligibility.evidences.each_with_index do |evidence, index|
          index.even? ? evidence.mark_as_outstanding : evidence.mark_as_verified
        end
        application.save!
        application
      end

      before do
        current_application
        family.latest_application_gid = current_application.to_global_id.uri.to_s
        family.save!
      end

      it 'returns a success result' do
        expect(result).to be_a_success
      end

      it 'determines the renewal application' do
        result
        expect(renewal_application.reload.current_state).to eq(:determined)
      end
      # rubocop:disable Layout/LineLength
      it 'retains evidence information from the current application to the renewal application' do
        result
        renewal_applicant.reload.individual_market_eligibility.evidences.each do |evidence|
          expect(evidence).to be_present
          expect(evidence.current_state).not_to eq(:pending)
          if evidence.due_on.present?
            expect(evidence.current_state).to eq(:outstanding)
            expect(
              evidence.verification_histories.any? do |history|
                history.action == 'retain_evidence_info_on_renewal' &&
                history.update_reason == "State updated from pending to #{evidence.current_state} and due date of #{evidence.due_on} copied from previous application #{current_application.hbx_id} application type faa due to annual eligibility redetermination."
                history.updated_by == 'system'
              end
            ).to be_truthy
          else
            expect(evidence.current_state).to eq(:verified)
          end

          expect(
            evidence.verification_histories.any? do |history|
              history.action == 'retain_evidence_info_on_renewal' &&
                history.update_reason == "State updated from pending to #{evidence.current_state} copied from previous application #{current_application.hbx_id} application type qhp due to annual eligibility redetermination."
              history.updated_by == 'system'
            end
          ).to be_truthy
        end
      end
      # rubocop:enable Layout/LineLength
    end

    context 'when:
      - renewal application exists in initial state
      - current application is Financial Assistance Application
      ' do
      let(:current_application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: 'determined', submitted_at: Time.now, assistance_year: TimeKeeper.date_of_record.year) }
      let(:applicant) do
        FactoryBot.create(
          :financial_assistance_applicant,
          gender: 'male',
          dob: Date.current - 25.years,
          is_incarcerated: false,
          indian_tribe_member: false,
          is_physically_disabled: false,
          no_ssn: '1',
          citizen_status: 'us_citizen',
          family_member_id: primary_applicant.id,
          person_hbx_id: person.hbx_id,
          application: current_application
        )
      end

      before do
        applicant.build_ivl_eligibility_with_evidences
        applicant.build_aptc_eligibilities_evidences
        applicant.eligibilities.flat_map(&:evidences).each_with_index do |evidence, ind|
          if ind.even?
            evidence.mark_as_outstanding
          else
            evidence.mark_as_verified
          end
        end
        current_application.save!
        family.assign_latest_application_gid
        family.save!
      end

      it 'returns a success result' do
        expect(result).to be_a_success
      end

      it 'determines the renewal application' do
        result
        expect(renewal_application.reload.current_state).to eq(:determined)
      end

      it 'retains evidence information from the current application to the renewal application' do
        result
        renewal_applicant.reload.individual_market_eligibility.evidences.each do |evidence|
          expect(evidence).to be_present
          expect(evidence.current_state).not_to eq(:pending)
          if evidence.due_on.present?
            expect(evidence.current_state).to eq(:outstanding)
            expect(
              evidence.verification_histories.any? do |history|
                history.action == 'retain_evidence_info_on_renewal' &&
                history.update_reason == "State updated from pending to #{evidence.current_state} " \
                "and due date of #{evidence.due_on} copied " \
                "from previous application #{current_application.hbx_id} " \
                "application type faa due to annual eligibility redetermination."
                history.updated_by == 'system'
              end
            ).to be_truthy
          else
            expect(evidence.current_state).to eq(:verified)
          end

          expect(
            evidence.verification_histories.any? do |history|
              history.action == 'retain_evidence_info_on_renewal' &&
              history.update_reason == "State updated from pending to #{evidence.current_state} " \
                "copied from previous application #{current_application.hbx_id} " \
                "application type qhp due to annual eligibility redetermination."
              history.updated_by == 'system'
            end
          ).to be_truthy
        end
      end
    end

    context 'when:
      - renewal application exists in initial state
      - current application is Financial Assistance Application
      - family member is added after the current application was determined
      ' do

      let(:current_application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: 'determined', submitted_at: Time.now, assistance_year: TimeKeeper.date_of_record.year) }
      let(:applicant) do
        FactoryBot.create(
          :financial_assistance_applicant,
          gender: 'male',
          dob: Date.current - 25.years,
          is_incarcerated: false,
          indian_tribe_member: false,
          is_physically_disabled: false,
          no_ssn: '1',
          citizen_status: 'us_citizen',
          family_member_id: primary_applicant.id,
          person_hbx_id: person.hbx_id,
          application: current_application,
          is_primary_applicant: true
        )
      end

      let(:dependent_person) do
        pr = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, ssn: "123-45-6789")
        person.ensure_relationship_with(pr, 'spouse')
        pr.save!
        pr
      end
      let(:dependent_family_member) { FactoryBot.create(:family_member, family: family, person: dependent_person) }

      let(:renewal_dependent_applicant) { FactoryBot.create(:individual_market_applicant, :with_person_name, application: renewal_application, family_member_id: dependent_family_member.id, is_primary_applicant: false) }

      let(:renewal_dependent_demographics) do
        demo = FactoryBot.create(:individual_market_demographics, applicant: renewal_dependent_applicant)
        renewal_dependent_applicant.build_individual_market_eligibility
        renewal_dependent_applicant.build_individual_market_evidences
        renewal_dependent_applicant.save!
        demo
      end

      before do
        renewal_dependent_demographics
        applicant.build_ivl_eligibility_with_evidences
        applicant.build_aptc_eligibilities_evidences
        applicant.eligibilities.flat_map(&:evidences).each_with_index do |evidence, ind|
          if ind.even?
            evidence.mark_as_outstanding
          else
            evidence.mark_as_verified
          end
        end
        current_application.save!
        family.assign_latest_application_gid
        dependent_family_member
        family.save!
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      end

      it 'returns a success result' do
        expect(result).to be_a_success
      end

      it 'determines the renewal application' do
        result
        expect(renewal_application.reload.current_state).to eq(:determined)
      end

      it 'retains evidence information from the current application to the renewal application' do
        result
        renewal_applicant.reload.individual_market_eligibility.evidences.each do |evidence|
          expect(evidence).to be_present
          expect(evidence.current_state).not_to eq(:pending)
          if evidence.due_on.present?
            expect(evidence.current_state).to eq(:outstanding)
            expect(
              evidence.verification_histories.any? do |history|
                history.action == 'retain_evidence_info_on_renewal' &&
                history.update_reason == "State updated from pending to #{evidence.current_state} " \
                "and due date of #{evidence.due_on} copied " \
                "from previous application #{current_application.hbx_id} " \
                "application type faa due to annual eligibility redetermination."
                history.updated_by == 'system'
              end
            ).to be_truthy
          else
            expect(evidence.current_state).to eq(:verified)
          end

          expect(
            evidence.verification_histories.any? do |history|
              history.action == 'retain_evidence_info_on_renewal' &&
              history.update_reason == "State updated from pending to #{evidence.current_state} " \
                "copied from previous application #{current_application.hbx_id} " \
                "application type qhp due to annual eligibility redetermination."
              history.updated_by == 'system'
            end
          ).to be_truthy
        end
      end

      it 'retains evidence information from the current application to the renewal application' do
        result
        renewal_dependent_applicant.reload.individual_market_eligibility.evidences.each do |evidence|
          expect(evidence).to be_present
          expect(evidence.current_state).to eq(:pending)
          expect(
            evidence.verification_histories.any? do |history|
              history.action == 'no_matching_applicant' &&
              history.update_reason == "family member is added after the #{current_application.assistance_year} application was determined, no prior evidence exists to retain on renewal"
              history.updated_by == 'system'
            end
          ).to be_truthy
        end
      end

      it 'retains evidence information from the current application to the renewal application' do
        result
        subject = family.reload.eligibility_determination.subjects.first
        eligibility_state = subject.eligibility_states[1]
        evidence_state = eligibility_state.evidence_states.first
        renewal_application.reload
        dependent = renewal_application.applicants[1]
        evidence = dependent.eligibilities.flatten[0].evidences.where(key: "citizenship_evidence").first
        expect(evidence_state.status).to be(evidence.current_state)
      end
    end

    context 'when:
      - renewal application exists in a non initial state
      ' do

      let(:renewal_application) { FactoryBot.create(:individual_market_application, :determined, :renewal, family_id: family.id) }

      it 'returns a failure result with an error message' do
        expect(result).to be_a_failure
        expect(result.failure).to eq("Application with ID #{renewal_application.id} is not in initial state.")
      end
    end

    context 'when:
      - renewal application id is invalid
      ' do

      let(:result) { subject.call(application_id: 'invalid_id') }

      it 'returns a failure result with an error message' do
        expect(result).to be_a_failure
        expect(result.failure).to eq("Application with ID invalid_id not found.")
      end
    end
  end
end
