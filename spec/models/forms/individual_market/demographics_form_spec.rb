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

      it "should validate ssn presence" do
        params[:ssn] = nil
        params[:no_ssn] = '0'
        form = described_class.new(params)
        expect(form.valid?).to be_truthy
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
    end
  end

end