# frozen_string_literal: true

require 'rails_helper'
require 'shared_contexts/dual_applications_with_eligible_family_setup'

RSpec.describe Operations::Families::Verifications::DmfDetermination::RequestDmfDetermination, dbclean: :after_each do
  include Dry::Monads[:result, :do]

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_ssn) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:job) { FactoryBot.create(:transmittable_job, :dmf_determination) }

  let(:payload) do
    {
      family_hbx_id: family.hbx_assigned_id,
      job_id: job.job_id
    }
  end

  before do
    allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)
  end

  context 'with no determined applications' do
    context "failure" do
      it "should fail without a family_hbx_id" do
        payload[:family_hbx_id] = nil
        result = described_class.new.call(payload)

        expect(result).to be_failure
      end

      it "should fail without a job_id" do
        payload[:job_id] = nil
        result = described_class.new.call(payload)

        expect(result).to be_failure
      end

      it "should fail if a family can't be found" do
        payload[:family_hbx_id] = '12345'
        result = described_class.new.call(payload)

        expect(result).to be_failure
      end

      it "should fail if a transmittable job can't be found" do
        payload[:job_id] = '12345'
        result = described_class.new.call(payload)

        expect(result).to be_failure
      end
    end

    context "success for one member family" do
      before do
        person.add_new_verification_type(VerificationType::ALIVE_STATUS)
        job.create_process_status
        Operations::Eligibilities::BuildFamilyDetermination.new.call({effective_date: Date.today, family: family})
        family.eligibility_determination.subjects[0].eligibility_states.last.update(is_eligible: true)
        @result = described_class.new.call(payload)
      end

      it "should pass" do
        expect(@result).to be_success
      end

      it "should create a verification type history element" do
        person.reload
        expect(person.alive_status.type_history_elements.count).to eq 1
        alive_status_element = person.alive_status.type_history_elements.last

        expect(alive_status_element.action).to eq 'DMF_Request_Submitted'
        expect(alive_status_element.modifier).to eq 'System'
      end

      it "should create a transmission" do
        transmission = ::Transmittable::Transmission.where(key: :dmf_determination_request).last
        expect(transmission).to be_truthy
        expect(transmission.process_status.latest_state).to eq :succeeded
      end

      it "should create a transaction" do
        transaction = ::Transmittable::Transaction.where(key: :dmf_determination_request).last
        expect(transaction).to be_truthy
        expect(transaction.json_payload).to be_truthy
        expect(transaction.process_status.latest_state).to eq :succeeded
      end

      it 'family should have a transaction' do
        expect(family.transactions.count).to eq 1
      end
    end

    context "success for multi-member family" do
      let(:spouse_dob) { Date.today - 55.years }
      let(:spouse_person) do
        per = FactoryBot.create(:person, :with_consumer_role, dob: spouse_dob, ssn: 101_011_012)
        person.ensure_relationship_with(per, 'spouse')
        per
      end
      let!(:spouse) { FactoryBot.create(:family_member, person: spouse_person, family: family) }

      before do
        person.add_new_verification_type(VerificationType::ALIVE_STATUS)
        spouse_person.add_new_verification_type(VerificationType::ALIVE_STATUS)
        job.create_process_status
        Operations::Eligibilities::BuildFamilyDetermination.new.call({effective_date: Date.today, family: family})
        family.eligibility_determination.subjects[0].eligibility_states.last.update(is_eligible: true)
        family.eligibility_determination.subjects[1].eligibility_states.last.update(is_eligible: true)
        @result = described_class.new.call(payload)
      end

      it "should pass" do
        expect(@result).to be_success
      end

      it "should create a verification type history element for primary" do
        person.reload
        expect(person.alive_status.type_history_elements.count).to eq 1
        alive_status_element = person.alive_status.type_history_elements.last

        expect(alive_status_element.action).to eq 'DMF_Request_Submitted'
        expect(alive_status_element.modifier).to eq 'System'
      end

      it "should create a verification type history element for primary" do
        spouse_person.reload
        expect(spouse_person.alive_status.type_history_elements.count).to eq 1
        alive_status_element = spouse_person.alive_status.type_history_elements.last

        expect(alive_status_element.action).to eq 'DMF_Request_Submitted'
        expect(alive_status_element.modifier).to eq 'System'
      end

      it "should create a transmission" do
        transmission = ::Transmittable::Transmission.where(key: :dmf_determination_request).last
        expect(transmission).to be_truthy
        expect(transmission.process_status.latest_state).to eq :succeeded
      end

      it "should create a transaction" do
        transaction = ::Transmittable::Transaction.where(key: :dmf_determination_request).last
        expect(transaction).to be_truthy
        expect(transaction.json_payload).to be_truthy
        expect(transaction.process_status.latest_state).to eq :succeeded
      end

      it 'family should have a transaction' do
        expect(family.transactions.count).to eq 1
      end
    end


    context "failure for all ineligible members" do
      let(:spouse_dob) { Date.today - 55.years }
      let(:spouse_person) do
        per = FactoryBot.create(:person, :with_consumer_role, dob: spouse_dob, ssn: 101_011_012)
        person.ensure_relationship_with(per, 'spouse')
        per
      end
      let!(:spouse) { FactoryBot.create(:family_member, person: spouse_person, family: family) }

      before do
        job.create_process_status
        Operations::Eligibilities::BuildFamilyDetermination.new.call({effective_date: Date.today, family: family})
        family.eligibility_determination.subjects[0].eligibility_states.last.update(is_eligible: false)
        @result = described_class.new.call(payload)
      end

      it "should pass" do
        expect(@result).to be_failure
      end

      it "should create a verification type history element for primary" do
        person.reload
        expect(person.alive_status.type_history_elements.count).to eq 2
        request_submitted_history_element = person.alive_status.type_history_elements.first
        request_failed_history_element = person.alive_status.type_history_elements.last

        expect(request_submitted_history_element.action).to eq 'DMF_Request_Submitted'
        expect(request_submitted_history_element.modifier).to eq 'System'
        expect(request_failed_history_element.action).to eq 'dmf_request_failed'
        expect(request_failed_history_element.modifier).to eq 'System'
      end

      it "should create a verification type history element for spouse" do
        spouse_person.reload
        expect(spouse_person.alive_status.type_history_elements.count).to eq 2
        request_submitted_history_element = spouse_person.alive_status.type_history_elements.first
        request_failed_history_element = spouse_person.alive_status.type_history_elements.last

        expect(request_submitted_history_element.action).to eq 'DMF_Request_Submitted'
        expect(request_submitted_history_element.modifier).to eq 'System'
        expect(request_failed_history_element.action).to eq 'dmf_request_failed'
        expect(request_failed_history_element.modifier).to eq 'System'
      end

      it "should create a transmission" do
        transmission = ::Transmittable::Transmission.where(key: :dmf_determination_request).last
        expect(transmission).to be_truthy
        expect(transmission.process_status.latest_state).to eq :failed
      end

      it "should create a transaction" do
        transaction = ::Transmittable::Transaction.where(key: :dmf_determination_request).last
        expect(transaction).to be_truthy
        expect(transaction.json_payload).to be_nil
        expect(transaction.process_status.latest_state).to eq :failed
      end

      it 'family should have a transaction' do
        expect(family.transactions.count).to eq 1
      end
    end

    context "failure for some ineligible members" do
      let(:spouse_dob) { Date.today - 55.years }
      let(:spouse_person) do
        per = FactoryBot.create(:person, :with_consumer_role, dob: spouse_dob, ssn: 101_011_012)
        person.ensure_relationship_with(per, 'spouse')
        per
      end
      let!(:spouse) { FactoryBot.create(:family_member, person: spouse_person, family: family) }

      before do
        job.create_process_status
        Operations::Eligibilities::BuildFamilyDetermination.new.call({effective_date: Date.today, family: family})
        family.eligibility_determination.subjects[0].eligibility_states.last.update(is_eligible: true)
        @result = described_class.new.call(payload)
      end

      it "should pass" do
        expect(@result).to be_success
      end

      it "should create a verification type history element for primary" do
        person.reload
        expect(person.alive_status.type_history_elements.count).to eq 1
        alive_status_element = person.alive_status.type_history_elements.last

        expect(alive_status_element.action).to eq 'DMF_Request_Submitted'
        expect(alive_status_element.modifier).to eq 'System'
      end

      it "should create a verification type history element for spouse" do
        spouse_person.reload
        expect(spouse_person.alive_status.type_history_elements.count).to eq 2
        request_submitted_history_element = spouse_person.alive_status.type_history_elements.first
        request_failed_history_element = spouse_person.alive_status.type_history_elements.last

        expect(request_submitted_history_element.action).to eq 'DMF_Request_Submitted'
        expect(request_submitted_history_element.modifier).to eq 'System'
        expect(request_failed_history_element.action).to eq 'dmf_request_failed'
        expect(request_failed_history_element.modifier).to eq 'System'
      end

      it "should create a transmission" do
        transmission = ::Transmittable::Transmission.where(key: :dmf_determination_request).last
        expect(transmission).to be_truthy
        expect(transmission.process_status.latest_state).to eq :succeeded
      end

      it "should create a transaction" do
        transaction = ::Transmittable::Transaction.where(key: :dmf_determination_request).last
        expect(transaction).to be_truthy
        expect(transaction.json_payload).to be_truthy
        expect(transaction.process_status.latest_state).to eq :succeeded
      end

      it 'family should have a transaction' do
        expect(family.transactions.count).to eq 1
      end
    end

    context 'person without alive status' do
      before do
        family
        person.verification_types.delete_all
        job.create_process_status
        Operations::Eligibilities::BuildFamilyDetermination.new.call({effective_date: Date.today, family: family})
        family.eligibility_determination.subjects[0].eligibility_states.last.update(is_eligible: true)
        @result = described_class.new.call(payload)
      end

      it "should not create a verification type history element for primary" do
        person.reload
        expect(person.verification_types.count).to eq 0
        expect(@result.success?).to eq true
      end
    end
  end

  context 'when a family has determined applications' do
    let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, :with_issuer_profile, metal_level_kind: :silver, benefit_market_kind: :aca_individual) }
    let!(:enrollment) do
      FactoryBot.create(:hbx_enrollment,
                        :with_enrollment_members,
                        family: family,
                        enrollment_members: family.family_members,
                        household: family.active_household,
                        coverage_kind: :health,
                        effective_on: Date.today,
                        kind: "individual",
                        product: product,
                        rating_area_id: person.consumer_role.rating_address.id,
                        consumer_role_id: family.primary_person.consumer_role.id,
                        aasm_state: 'coverage_selected')
    end

    include_context 'dual applications with eligible family setup'

    context 'with a financial assistance application' do
      let(:current_application) { create_financial_assistance_application }
      let(:applicant) { current_application.primary_applicant }

      before do
        Operations::Eligibilities::BuildFamilyDetermination.new.call({effective_date: Date.today, family: family})
        family.eligibility_determination.subjects[0].eligibility_states.last.update(is_eligible: true)
      end

      it 'should return success' do
        result = described_class.new.call(payload)

        expect(result).to be_success
      end

      context 'when applicant does not have alive evidence' do
        before do
          applicant.individual_market_eligibility.alive_evidence.destroy
        end

        it 'should build alive evidence for applicants in the latest application' do
          expect(applicant&.individual_market_eligibility&.alive_evidence).to be_nil

          described_class.new.call(payload)
          current_application.reload

          expect(applicant&.individual_market_eligibility&.alive_evidence).to be_present
        end
      end
    end

    context 'with an individual market application' do
      let(:current_application) { create_individual_market_application }
      let(:applicant) { current_application.primary_applicant }

      before do
        Operations::Eligibilities::BuildFamilyDetermination.new.call({effective_date: Date.today, family: family})
        family.eligibility_determination.subjects[0].eligibility_states.last.update(is_eligible: true)
      end

      it 'should return success' do
        result = described_class.new.call(payload)

        expect(result).to be_success
      end

      context 'when applicant does not have alive evidence' do
        before do
          applicant.individual_market_eligibility.alive_evidence.destroy
        end

        it 'should build alive evidence for applicants in the latest application' do
          expect(applicant.individual_market_eligibility&.alive_evidence).to be_nil

          described_class.new.call(payload)
          current_application.reload

          expect(applicant.individual_market_eligibility&.alive_evidence).to be_present
        end
      end
    end
  end
end
