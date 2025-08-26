# frozen_string_literal: true

require "rails_helper"

describe Forms::Locations::AddressForm, "validations" do

  subject do
    Forms::Locations::AddressForm.new
  end

  context 'with missing params' do

    before :each do
      subject.valid?
    end

    it "should validate address_1" do
      expect(subject).to have_errors_on(:address_1)
    end

    it "should validate city" do
      expect(subject).to have_errors_on(:city)
    end

    it "should validate state" do
      expect(subject).to have_errors_on(:state)
    end

    it "should validate zip" do
      expect(subject).to have_errors_on(:zip)
    end

  end

  context 'with invalid params' do
    let(:invalid_params) do
      {
        kind: 'home',
        address_1: '123 Main St',
        city: 'Anytown',
        state: 'CA',
        zip: '12345',
        county: 'Any County'
      }
    end

    it 'kind not in the list' do
      invalid_params[:kind] = "invalid"
      subject.attributes = invalid_params
      expect(subject).to be_invalid
      expect(subject.errors.full_messages).to include("Kind is not included in the list")
    end

    it 'zip is not numeric' do
      invalid_params[:zip] = "oneto"
      subject.attributes = invalid_params
      expect(subject).to be_invalid
      expect(subject.errors.full_messages).to include("Zip should be 5 digits")
    end

    it 'zip is not 5 digits' do
      invalid_params[:zip] = 123_456
      subject.attributes = invalid_params
      expect(subject).to be_invalid
      expect(subject.errors.full_messages).to include("Zip should be 5 digits")
    end

    it 'state is not in the list' do
      invalid_params[:state] = "XX"
      subject.attributes = invalid_params
      expect(subject).to be_invalid
      expect(subject.errors.full_messages).to include("State is not included in the list")
    end

    context 'with a destroyed address' do
      it 'should be valid with an id and destroy set to true' do
        invalid_params[:state] = "XX"
        invalid_params[:id] = BSON::ObjectId.new
        invalid_params[:_destroy] = "true"
        subject.attributes = invalid_params
        expect(subject).to be_valid
      end

      it 'should be invalid without an id' do
        invalid_params[:state] = "XX"
        invalid_params[:id] = nil
        invalid_params[:_destroy] = "true"
        subject.attributes = invalid_params
        expect(subject).to be_invalid
      end
    end
  end

  context 'with valid params' do
    it 'should be valid' do
      subject.kind = 'home'
      subject.address_1 = '123 Main St'
      subject.city = 'Anytown'
      subject.state = 'CA'
      subject.zip = '12345'
      subject.county = 'Any County'
      expect(subject).to be_valid
    end
  end
end
