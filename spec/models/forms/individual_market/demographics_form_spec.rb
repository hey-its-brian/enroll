# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Forms::IndividualMarket::DemographicsForm, type: :model, dbclean: :after_each do

  let(:params) do
    {
      dob: "1990-01-01",
      gender: "male",
      ssn: "263542644",
      no_ssn: 0,
      us_citizen: 'true',
      naturalized_citizen: 'false',
      eligible_immigration_status: 'false',
      indian_tribe_member: 'false',
      tribal_state: '',
      tribe_codes: [],
      is_incarcerated: 'false',
      ethnicity: [],
      is_applying_coverage: true
    }
  end

  context 'with valid params' do

    before do
      @form = described_class.new(params)
    end

    it 'should build the form' do
      expect(@form).to be_truthy
    end

    it 'should be valid' do
      expect(@form).to be_valid
    end

    it 'should have no errors' do
      expect(@form.errors.full_messages).to be_empty
    end

  end

  context 'validations' do

    it 'should fail when gender is missing' do
      params.delete(:gender)
      subject.attributes = params
      expect(subject.valid?).to be_falsey
      expect(subject.errors.full_messages.first).to include("Gender can't be blank")
    end

    it 'should fail when dob is missing' do
      params.delete(:dob)
      subject.attributes = params
      expect(subject.valid?).to be_falsey
      expect(subject.errors.full_messages.first).to include("Dob can't be blank")
    end

    it 'should fail when ssn is not 9 digits' do
      params[:ssn] = '12345678910'
      subject.attributes = params
      expect(subject.valid?).to be_falsey
      expect(subject.errors.full_messages.first).to include("SSN must be 9 digits")
    end

    it 'should fail when ssn is not a number' do
      params[:ssn] = '123456789a'
      subject.attributes = params
      expect(subject.valid?).to be_falsey
      expect(subject.errors.full_messages.first).to include("SSN must be 9 digits")
    end

    describe "when applying for coverage" do

      before do
        params[:is_applying_coverage] = true
      end

      it "should validate ssn presence" do
        params[:ssn] = nil
        params[:no_ssn] = '0'
        form = described_class.new(params)
        expect(form.valid?).to be_falsey
        expect(form.errors.full_messages.first).to include("SSN is required")
      end

      it "should validate citizen status" do
        params[:us_citizen] = nil
        form = described_class.new(params)
        expect(form.valid?).to be_falsey
        expect(form.errors.full_messages.first).to include("Citizenship status is required")
      end

      it "should validate naturalized citizen" do
        params[:us_citizen] = true
        params[:naturalized_citizen] = nil
        form = described_class.new(params)
        expect(form.valid?).to be_falsey
        expect(form.errors.full_messages.first).to include("Naturalized citizen is required")
      end

      it "should validate incarceration status" do
        params[:is_incarcerated] = nil
        form = described_class.new(params)
        expect(form.valid?).to be_falsey
        expect(form.errors.full_messages.first).to include("Incarceration status is required")
      end

      it "should validate native american status" do
        params[:indian_tribe_member] = nil
        form = described_class.new(params)
        expect(form.valid?).to be_falsey
        expect(form.errors.full_messages.first).to include("Native american / alaska native status is required")
      end
    end

    describe "when not applying for coverage" do

      before do
        params[:is_applying_coverage] = false
      end

      it "should validate citizen status" do
        params[:us_citizen] = nil
        form = described_class.new(params)
        expect(form.valid?).to be_truthy
      end

      it "should validate naturalized citizen" do
        params[:us_citizen] = true
        params[:naturalized_citizen] = nil
        form = described_class.new(params)
        expect(form.valid?).to be_truthy
      end

      it "should validate incarceration status" do
        params[:is_incarcerated] = nil
        form = described_class.new(params)
        expect(form.valid?).to be_truthy
      end

      it "should validate native american status" do
        params[:indian_tribe_member] = nil
        form = described_class.new(params)
        expect(form.valid?).to be_truthy
      end

      context 'validate no_ssn_or_ssn' do
        it 'should be valid when no_ssn is true and encrypted_ssn is nil' do
          params[:no_ssn] = 1
          params[:encrypted_ssn] = nil
          params[:ssn] = nil
          params[:existing_ssn] = nil
          @applicant_form = described_class.new(params)
          expect(@applicant_form.valid?).to be_truthy
        end

        it 'should be valid when no_ssn is false and encrypted_ssn is not nil' do
          params[:no_ssn] = 0
          params[:encrypted_ssn] = SymmetricEncryption.encrypt("123456789")
          params[:ssn] = nil
          params[:existing_ssn] = nil
          @applicant_form = described_class.new(params)
          expect(@applicant_form.valid?).to be_truthy
        end

        it 'should should have a new encrypted_ssn when no_ssn is false and encrypted_ssn is not nil' do
          params[:no_ssn] = 0
          params[:encrypted_ssn] = SymmetricEncryption.encrypt("123456789")
          params[:ssn] = "123456789"
          params[:existing_ssn] = SymmetricEncryption.encrypt("423356785")
          @applicant_form = described_class.new(params)
          expect(@applicant_form.to_h[:encrypted_ssn]).to eq(SymmetricEncryption.encrypt("123456789"))
        end

        it 'should be valid when no_ssn is false and ssn is not nil' do
          params[:no_ssn] = 0
          params[:encrypted_ssn] = nil
          params[:ssn] = "123456789"
          @applicant_form = described_class.new(params)
          expect(@applicant_form.valid?).to be_truthy
        end

        it 'should be valid when no_ssn is false and existing ssn' do
          params[:no_ssn] = 0
          params[:encrypted_ssn] = nil
          params[:ssn] = nil
          params[:existing_ssn] = "423456789"
          @applicant_form = described_class.new(params)
          expect(@applicant_form.valid?).to be_truthy
        end

        it 'should be invalid when no_ssn is false and no ssn of any type' do
          params[:no_ssn] = 0
          params[:encrypted_ssn] = nil
          params[:ssn] = nil
          params[:existing_ssn] = nil
          @applicant_form = described_class.new(params)
          expect(@applicant_form.valid?).to be_falsey
        end

        it 'should be valid when no_ssn is not present, ssn is not present, and existing_no_ssn is true' do
          params[:no_ssn] = nil
          params[:encrypted_ssn] = nil
          params[:ssn] = nil
          params[:existing_no_ssn] = true
          @applicant_form = described_class.new(params)
          expect(@applicant_form.valid?).to be_truthy
        end

        it 'should be invalid when no_ssn is not present, ssn is not present, and existing_no_ssn is false' do
          params[:no_ssn] = nil
          params[:existing_no_ssn] = false
          params[:encrypted_ssn] = nil
          params[:ssn] = nil
          params[:existing_ssn] = nil
          @applicant_form = described_class.new(params)
          expect(@applicant_form.valid?).to be_falsey
        end

        it 'should be valid when no_ssn is false, ssn is present, and existing_no_ssn is true' do
          params[:no_ssn] = 0
          params[:encrypted_ssn] = SymmetricEncryption.encrypt("123456789")
          params[:ssn] = "123456789"
          params[:existing_no_ssn] = true
          @applicant_form = described_class.new(params)
          expect(@applicant_form.valid?).to be_truthy
        end
      end
    end

    describe "citizen_status" do
      it "should be valid when us_citizen is true" do
        params[:us_citizen] = true
        form = described_class.new(params)
        expect(form.valid?).to be_truthy
        expect(form.to_h[:citizen_status]).to eq("us_citizen")
      end

      it "should set citizen status to not_lawfully_present_in_us when us_citizen is false and eligible_immigration_status is not present" do
        params[:us_citizen] = false
        params[:eligible_immigration_status] = nil
        form = described_class.new(params)
        expect(form.valid?).to be_truthy
        expect(form.to_h[:citizen_status]).to eq("not_lawfully_present_in_us")
      end
    end
  end

end