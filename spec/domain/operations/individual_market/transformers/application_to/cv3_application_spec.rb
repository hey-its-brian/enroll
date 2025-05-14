# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::Transformers::ApplicationTo::Cv3Application do
  let(:application) { FactoryBot.create(:individual_market_application, :with_primary) }
  let(:applicant1) { application.primary_applicant }
  let(:applicant2) { FactoryBot.create(:individual_market_applicant, :dependent, :with_person_name, :with_demographics, application: application) }
  let(:relationship) do
    FactoryBot.create(
      :individual_market_relationship,
      application: application,
      source_id: applicant1.id,
      relative_id: applicant2.id,
      kind: 'spouse'
    )
  end
  let(:ivl_eligibility) { application.applicants.first.eligibilities.first }
  let(:evidence) { FactoryBot.create(:alive_evidence, eligibility: ivl_eligibility) }
  let(:attestation) { FactoryBot.create(:individual_market_attestation, application: application) }

  before do
    application.relationships << relationship
    application.attestation = attestation
    application.save
    @result = subject.call(application)
    @payload = @result.value!
  end

  subject { described_class.new }

  describe '#call' do
    context 'with valid application' do
      it 'returns success with transformed payload' do

        expect(@result).to be_success
        expect(@result.value!).to be_a(Hash)
      end

      it 'transforms application attributes correctly' do
        expect(@payload[:family_reference][:hbx_id]).to eq(application.family.hbx_assigned_id.to_s)
        expect(@payload[:assistance_year]).to eq(application.assistance_year)
        expect(@payload[:hbx_id]).to eq(application.hbx_id)
        expect(@payload[:effective_on]).to eq(application.effective_on)
        expect(@payload[:submitted_at]).to eq(application.submitted_at)
        expect(@payload[:origin]).to eq(application.origin)
        expect(@payload[:generation_reason]).to eq(application.generation_reason)
        expect(@payload[:current_state]).to eq(application.current_state)
      end

      it 'transforms applicants correctly' do
        expect(@payload[:applicants]).to be_an(Array)
        expect(@payload[:applicants].size).to eq(application.applicants.size)

        primary_applicant = @payload[:applicants].find { |a| a[:is_primary_applicant] }
        expect(primary_applicant).to be_present
      end

      it 'transforms applicant person_name correctly' do
        primary_applicant = @payload[:applicants].find { |a| a[:is_primary_applicant] }
        name = primary_applicant[:person_name]

        expect(name[:given_name]).to eq(applicant1.person_name.given_name)
        expect(name[:family_name]).to eq(applicant1.person_name.family_name)
      end

      it 'transforms applicant demographics correctly' do
        primary_applicant = @payload[:applicants].find { |a| a[:is_primary_applicant] }
        demographics = primary_applicant[:demographics]

        expect(demographics[:gender]).to eq(applicant1.demographics.gender)
        expect(demographics[:dob]).to eq(applicant1.demographics.dob)
      end

      it 'transforms relationships correctly' do
        expect(@payload[:relationships]).to be_an(Array)
        expect(@payload[:relationships].size).to eq(1)

        rel = @payload[:relationships].first
        expect(rel[:source_reference][:first_name]).to eq(applicant1.person_name.given_name)
        expect(rel[:kind]).to eq('spouse')
      end

      it 'transforms attestation if present' do
        expect(@payload[:attestation]).to be_a(Hash)
      end

      it 'excludes created_at and updated_at timestamps' do
        expect(@payload).not_to have_key(:created_at)
        expect(@payload).not_to have_key(:updated_at)

        applicant = @payload[:applicants].first
        expect(applicant).not_to have_key(:created_at)
        expect(applicant).not_to have_key(:updated_at)

        person_name = applicant[:person_name]
        expect(person_name).not_to have_key(:created_at)
        expect(person_name).not_to have_key(:updated_at)
      end
    end

    context 'with invalid application' do
      it 'returns failure when not an IndividualMarket::Application' do
        result = subject.call(Object.new)

        expect(result).to be_failure
        expect(result.failure).to include("Should be an instance of IndividualMarket::Application")
      end

      it 'returns failure when application not persisted' do
        new_app = FactoryBot.build(:individual_market_application)
        result = subject.call(new_app)

        expect(result).to be_failure
        expect(result.failure).to include("Application is not persisted")
      end
    end
  end

  describe 'recursive handling of embedded documents' do
    context 'when applicant has embedded documents' do
      before do
        application.submitted_at = TimeKeeper.date_of_record
        address = FactoryBot.create(:location_address, addressable: applicant1)
        applicant1.addresses << address
        application.save!
        application.reload

        @result = subject.call(application)
        @payload = @result.value!
      end

      it 'transforms addresses correctly' do
        primary_applicant = @payload[:applicants].find { |a| a[:is_primary_applicant] }
        expect(primary_applicant[:addresses]).to be_an(Array)
        expect(primary_applicant[:addresses].first[:kind]).to eq(applicant1.addresses.first.kind)
        expect(primary_applicant[:addresses].first[:city]).to eq(applicant1.addresses.first.city)
        expect(primary_applicant[:addresses].first).not_to have_key(:created_at)
      end

      it 'validate payload' do
        payload_valid = AcaEntities::IndividualMarket::Operations::Applications::Create.new.call(@payload)
        expect(payload_valid).to be_success
      end
    end
  end

  describe 'handling missing optional fields' do
    before do
      @result = subject.call(application)
      @payload = @result.value!
    end
    it 'handles missing attestation' do
      application.attestation = nil
      expect(@payload[:attestation]).to be_blank
    end

    it 'handles missing person_name' do
      applicant = FactoryBot.create(:individual_market_applicant, application: application)
      applicant.person_name = nil
      applicant.save!
      application.reload

      found_applicant = @payload[:applicants].find { |a| a[:_id] == applicant.id.to_s }
      expect(found_applicant[:person_name]).to be_blank if found_applicant
    end
  end
end
