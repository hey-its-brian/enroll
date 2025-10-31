# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/shared_contexts/valid_cv3_application_setup.rb')

RSpec.describe ::Operations::Eligibilities::V3::IndividualMarket::SsaVlpVerification, type: :model, dbclean: :after_each do
  include_context "valid cv3 application setup"

  before :all do
    DatabaseCleaner.clean
  end
  let(:subject) { described_class.new }

  describe '#call' do
    before do
      applicant.build_ivl_eligibility_with_evidences
      applicant.save
    end

    context 'with valid application' do
      it 'returns success with message' do
        result = subject.call({call_type: 'application_determination', application: application})
        expect(result).to be_success
        eligibility = application.applicants.first.eligibilities.first
        evidence = eligibility.evidences.where(
          :key.in => Operations::Eligibilities::V3::IndividualMarket::SsaVlpVerification::EVIDENCE_KEYS
        ).first
        expect(evidence.verification_histories.first.action).to eq('SSA VLP Hub Request')
        expect(::Transmittable::Job.first.process_status.latest_state).to eq(:transmitted)
        expect(::Transmittable::Transmission.first.process_status.latest_state).to eq(:transmitted)
        expect(::Transmittable::Transaction.first.process_status.latest_state).to eq(:transmitted)
      end
    end

    context 'with valid application for hub call' do
      it 'returns success with message' do
        result = subject.call({call_type: 'application_determination',
                               application: application,
                               updated_by: 'hub_call',
                               request_hbx_ids: [application.applicants.first.person_hbx_id]})
        expect(result).to be_success
        eligibility = application.applicants.first.eligibilities.first
        evidence = eligibility.evidences.where(key: :social_security_number_evidence).first
        expect(evidence.verification_histories.first.action).to eq('SSA VLP Hub Request')
        expect(evidence.verification_histories.first.updated_by).to eq('hub_call')
        expect(::Transmittable::Job.first.process_status.latest_state).to eq(:transmitted)
      end
    end

    context 'with request_hbx_ids' do
      let!(:second_person) { FactoryBot.create(:person, :with_consumer_role, first_name: 'Jane', last_name: 'Doe') }
      let!(:second_family_member) { FactoryBot.create(:family_member, family: family, person: second_person) }
      let!(:second_applicant) do
        second_app = FactoryBot.create(:financial_assistance_applicant,
                                       application: application,
                                       family_member_id: second_family_member.id,
                                       person_hbx_id: second_person.hbx_id,
                                       first_name: second_person.first_name,
                                       last_name: second_person.last_name,
                                       gender: second_person.gender,
                                       dob: second_person.dob)
        eligibility = FactoryBot.build(:individual_market_eligibility, eligible: second_app)
        eligibility.evidences = [FactoryBot.build(:social_security_number_evidence, :verified, eligibility: eligibility)]
        second_app.eligibilities = [eligibility]
        second_app.save
        second_app
      end

      it 'only updates verifications for requested applicants' do
        result = subject.call({call_type: 'application_determination',
                               application: application,
                               updated_by: 'hub_call',
                               request_hbx_ids: [application.applicants.first.person_hbx_id]})
        expect(result).to be_success

        first_applicant_evidence = application.applicants.first.individual_market_eligibility.social_security_number_evidence
        expect(first_applicant_evidence.verification_histories.count).to eq(1)
        expect(first_applicant_evidence.pending?).to be_truthy
        expect(first_applicant_evidence.verification_histories.first.action).to eq('SSA VLP Hub Request')

        second_applicant_evidence = application.applicants.second.reload.individual_market_eligibility.social_security_number_evidence
        expect(second_applicant_evidence.verification_histories).to be_empty
        expect(second_applicant_evidence.verified?).to be_truthy
      end
    end

    context 'with app_entity provided' do
      let(:entity_response) { Operations::Fdsh::BuildAndValidateApplicationPayload.new.call(application) }

      it 'returns success with app_entity' do
        result = subject.call({call_type: 'application_determination', application: application, application_entity: entity_response})
        expect(result).to be_success
        expect(::Transmittable::Job.first.process_status.latest_state).to eq(:transmitted)
        expect(::Transmittable::Transmission.first.process_status.latest_state).to eq(:transmitted)
        expect(::Transmittable::Transaction.first.process_status.latest_state).to eq(:transmitted)
      end
    end

    context 'with invalid application type' do
      let(:invalid_app) { double('InvalidApp', class: 'SomeClass') }

      it 'returns failure with error message' do
        result = subject.call({call_type: 'application_determination', application: invalid_app})
        expect(result).to be_failure
        expect(result.failure).to include("Invalid application type")
      end
    end

    context 'when build_app_entity fails' do
      before do
        allow(subject).to receive(:build_app_entity).and_return(Dry::Monads::Result::Failure.new("Failed to build entity"))
      end

      it 'returns the failure' do
        result = subject.call({call_type: 'application_determination', application: application})
        expect(result).to be_failure
        expect(result.failure).to eq("Failed to build entity")
      end
    end

    context 'when publish fails' do
      let(:app_entity) { {test: "test"} }
      before do
        allow(subject).to receive(:build_app_entity).and_return(Dry::Monads::Result::Success.new(app_entity))
        allow(subject).to receive(:event).and_raise(StandardError.new("Publish error"))
      end

      it 'returns failure with error message' do
        result = subject.call({call_type: 'application_determination', application: application})
        expect(result).to be_failure
        expect(result.failure).to include("Failed to publish")
      end
    end
  end
end
