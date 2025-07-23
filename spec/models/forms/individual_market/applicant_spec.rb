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

  let(:mailing_address) do
    application.applicants.last.addresses.find { |a| a.kind == "mailing" }
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
                                        _destroy: 'false'},
                              :'1' => { kind: 'mailing',
                                        address_1: '1234 Main St',
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

    it 'should create a new home address if address_same_as_primary is true' do
      @applicant_form = described_class.new(params)
      @applicant_form.save
      application.reload
      expect(application.applicants.last.home_address).to be_present
    end

    it 'should create a new mailing address' do
      @applicant_form = described_class.new(params)
      @applicant_form.save
      application.reload
      expect(application.applicants.last.mailing_address).to be_present
    end

    it 'should be able to remove the mailing address' do
      params[:addresses_attributes][:'1'][:_destroy] = 'true'
      params[:addresses_attributes][:'1'][:id] = BSON::ObjectId.new
      @applicant_form = described_class.new(params)
      @applicant_form.save
      application.reload
      application.applicants.last.reload
      expect(application.applicants.last.mailing_address).not_to be_present
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

    it 'should return false when the applicant is invalid' do
      params[:person_name_attributes][:given_name] = nil
      @applicant_form = described_class.new(params)
      expect(@applicant_form.save.first).to be_falsey
    end
  end

  context 'validate no_ssn_or_ssn' do
    let(:input_applicant) {spouse_applicant}

    it 'should be valid when no_ssn is true and encrypted_ssn is nil' do
      params[:demographics_attributes][:no_ssn] = 1
      params[:demographics_attributes][:encrypted_ssn] = nil
      params[:demographics_attributes][:ssn] = nil
      @applicant_form = described_class.new(params)
      expect(@applicant_form.valid?).to be_truthy
    end

    it 'should be valid when no_ssn is false and encrypted_ssn is not nil' do
      params[:demographics_attributes][:no_ssn] = 0
      params[:demographics_attributes][:encrypted_ssn] = SymmetricEncryption.encrypt("123456789")
      params[:demographics_attributes][:ssn] = nil
      @applicant_form = described_class.new(params)
      expect(@applicant_form.valid?).to be_truthy
    end

    it 'should be valid when no_ssn is false and ssn is not nil' do
      params[:demographics_attributes][:no_ssn] = 0
      params[:demographics_attributes][:encrypted_ssn] = nil
      params[:demographics_attributes][:ssn] = "123456789"
      @applicant_form = described_class.new(params)
      expect(@applicant_form.valid?).to be_truthy
    end

    it 'should be valid when no_ssn is false and existing ssn' do
      params[:demographics_attributes][:no_ssn] = 0
      params[:demographics_attributes][:encrypted_ssn] = nil
      params[:demographics_attributes][:ssn] = nil
      @applicant_form = described_class.new(params)
      expect(@applicant_form.valid?).to be_falsey
    end

    it 'should be invalid when no_ssn is false and no ssn of any type' do
      params[:demographics_attributes][:no_ssn] = 0
      params[:demographics_attributes][:encrypted_ssn] = nil
      params[:demographics_attributes][:ssn] = nil
      input_applicant.demographics.update(encrypted_ssn: nil, ssn: nil)
      @applicant_form = described_class.new(params)
      expect(@applicant_form.valid?).to be_falsey
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

  context 'an existing applicant with ssn' do
    let(:input_applicant) {spouse_applicant}

    it 'should still have the same encrypted ssn even if not in the params' do
      [:ssn, :encrypted_ssn].each do |key|
        params[:demographics_attributes].delete(key)
      end
      encrypted_ssn = input_applicant.demographics.encrypted_ssn
      @applicant_form = described_class.new(params)
      @applicant_form.save
      expect(@applicant_form.demographics.encrypted_ssn).to eq(encrypted_ssn)
      application.reload
      expect(application.applicants.last.demographics.encrypted_ssn).to eq(encrypted_ssn)
    end

    it 'should not have the same ssn if ssn is in the params' do
      params[:demographics_attributes][:ssn] = "423456789"
      params[:demographics_attributes][:encrypted_ssn] = nil
      @applicant_form = described_class.new(params)
      @applicant_form.save
      expect(@applicant_form.demographics.ssn).to eq("423456789")
      application.reload
      expect(application.applicants.last.demographics.encrypted_ssn).to eq(SymmetricEncryption.encrypt("423456789"))
      expect(application.applicants.last.demographics.ssn).to eq("423456789")
    end

    it 'should not have the same ssn if encrypted_ssn is in the params' do
      params[:demographics_attributes][:ssn] = nil
      params[:demographics_attributes][:encrypted_ssn] = SymmetricEncryption.encrypt("423456789")
      @applicant_form = described_class.new(params)
      @applicant_form.save
      expect(@applicant_form.demographics.ssn).to eq(nil)
      application.reload
      expect(application.applicants.last.demographics.encrypted_ssn).to eq(SymmetricEncryption.encrypt("423456789"))
      expect(application.applicants.last.demographics.ssn).to eq("423456789")
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

  context 'when dependent ssn is taken' do
    let(:input_applicant) {spouse_applicant}
    let(:existing_person) { FactoryBot.create(:person, :with_consumer_role, first_name: spouse_applicant.person_name.given_name, last_name: spouse_applicant.person_name.family_name, dob: spouse_applicant.demographics.dob) }

    before do
      existing_person.update(ssn: params[:demographics_attributes][:ssn])
    end

    it 'should save when ssn, name and dob are the same as an existing person' do
      applicant_form = described_class.new(params)
      applicant_form.save
      expect(applicant_form.errors.full_messages).to be_empty
    end

    it 'should not save when ssn and name but not dob are the same as an existing person' do
      existing_person.update(dob: existing_person.dob + 1.day)
      applicant_form = described_class.new(params)
      applicant_form.save
      expect(applicant_form.save[0]).to be_falsey
      expect(applicant_form.errors.full_messages).to include("ssn is already taken")
    end
  end
end
