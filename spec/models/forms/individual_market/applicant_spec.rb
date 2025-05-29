# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Forms::IndividualMarket::Applicant, type: :model, dbclean: :after_each do
  let(:application) do
    FactoryBot.create(:individual_market_application, :with_applicants)
  end

  let(:applicant) do
    application.applicants.first
  end

  let(:spouse_applicant) do
    application.applicants.last
  end

  let(:params) do
    {
      is_dependent: !input_applicant.is_primary_applicant,
      is_primary_applicant: "false",
      person_name_attributes: {
        given_name: input_applicant.person_name.given_name,
        family_name: input_applicant.person_name.family_name
      },
      demographics_attributes: {
        dob: input_applicant.demographics.dob,
        gender: input_applicant.demographics.gender,
        ssn: "263542644",
        encrypted_ssn: input_applicant.demographics.encrypted_ssn,
        no_ssn: 0,
        us_citizen: 'true',
        naturalized_citizen: 'false',
        eligible_immigration_status: 'false',
        indian_tribe_member: 'false',
        tribal_state: '',
        tribe_codes: [],
        is_incarcerated: 'false',
        ethnicity: []
      },
      relationship: "spouse",
      is_applying_coverage: input_applicant.is_applying_coverage,
      age_off_excluded: "true",
      address_same_as_primary: input_applicant.address_same_as_primary,
      addresses_attributes: { :'0' => { kind: 'home',
                                        address_1: '123 Main St',
                                        address_2: '',
                                        city: 'Anytown',
                                        state: 'CA',
                                        zip: '12345',
                                        county: 'Any County',
                                        _destroy: 'false'}},
      application_id: application.id,
      id: input_applicant.id
    }
  end

  context 'with valid params' do
    let(:input_applicant) {spouse_applicant}

    before do
      @applicant_form = described_class.new(params)
    end

    it 'should save the applicant' do
      expect(@applicant_form.save).to be_truthy
    end

    it 'should be valid' do
      expect(@applicant_form).to be_valid
    end

    it 'should have no errors' do
      expect(@applicant_form.errors.full_messages).to be_empty
    end

    it 'should initialize the person name form' do
      expect(@applicant_form.person_name).to be_a(Forms::IndividualMarket::PersonNameForm)
    end

    it 'should initialize the demographics form' do
      expect(@applicant_form.demographics).to be_a(Forms::IndividualMarket::DemographicsForm)
    end

    it 'should initialize the addresses forms' do
      expect(@applicant_form.address_forms).to be_a(Array)
      expect(@applicant_form.address_forms.first).to be_a(Forms::Locations::AddressForm)
    end

    it 'should have the age off excluded attribute' do
      expect(@applicant_form.age_off_excluded).to eq("true")
    end

    it 'should have the address same as primary attribute' do
      expect(@applicant_form.address_same_as_primary).to eq(true)
    end

    it 'should build the relationship' do
      @applicant_form.save
      application.reload
      expect(application.relationships.where(source_id: input_applicant.id, kind: "spouse").count).to eq(1)
    end

    it 'should build the eligibilities' do
      expect(@applicant_form.eligibilities.count).to eq(1)
    end

    it 'should handle address changes' do
      @applicant_form = described_class.new(params)
      @applicant_form.save
      application.reload
      expect(application.applicants.last.addresses.count).to eq(0)
    end
  end

  context 'with invalid params' do
    let(:input_applicant) {spouse_applicant}

    it 'should fail to save when the applicant is missing a required field' do
      params[:person_name_attributes][:given_name] = nil
      @applicant_form = described_class.new(params)
      @applicant_form.save
      expect(@applicant_form.errors.full_messages).to include("given_name can't be blank")
    end

  end

  context 'it should verify_unique_dependent' do
    let(:input_applicant) {spouse_applicant}

    it 'should verify_unique_dependent' do
      params.delete(:id)
      @applicant_form = described_class.new(params)
      expect(@applicant_form.valid?).to be_falsey
      expect(@applicant_form.errors.full_messages.first).to include("Cannot add the duplicate members as they are present on enrollments/tax households.")
    end

    it 'should allow matching dependents with different dobs' do
      params.delete(:id)
      params[:demographics_attributes][:dob] = spouse_applicant.demographics.dob + 1.day
      @applicant_form = described_class.new(params)
      expect(@applicant_form.valid?).to be_truthy
    end

    it 'should allow matching dependents with different first names and same dobs' do
      params.delete(:id)
      params[:person_name_attributes][:given_name] = "#{spouse_applicant.person_name.given_name}X"
      @applicant_form = described_class.new(params)
      expect(@applicant_form.valid?).to be_truthy
    end
  end

  context 'it should build an individual market applicant' do
    let(:input_applicant) {spouse_applicant}

    it 'should build and save a new applicant' do
      params.delete(:id)
      params[:demographics_attributes][:dob] = spouse_applicant.demographics.dob + 1.day
      @applicant_form = described_class.new(params)
      expect(@applicant_form.valid?).to be_truthy
      @applicant_form.save
      application.reload
      expect(application.applicants.count).to eq(3)
    end
  end
end