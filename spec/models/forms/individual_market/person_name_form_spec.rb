# frozen_string_literal: true

require "rails_helper"

describe Forms::IndividualMarket::PersonNameForm, "validations" do

  subject do
    Forms::IndividualMarket::PersonNameForm.new
  end

  context 'with missing params' do

    before :each do
      subject.valid?
    end

    it "should validate given_name" do
      expect(subject).to have_errors_on(:given_name)
    end

    it "should validate family_name" do
      expect(subject).to have_errors_on(:family_name)
    end
  end

  context 'with valid params' do
    it 'should be valid' do
      subject.given_name = 'John'
      subject.family_name = 'Doe'
      expect(subject).to be_valid
    end
  end

  context 'with suffix' do
    it 'should be invalid if not on list' do
      subject.given_name = 'John'
      subject.family_name = 'Doe'
      subject.name_sfx = 'Invalid'
      expect(subject).to be_invalid
      expect(subject.errors.full_messages).to include("Name sfx is not a valid suffix")
    end

    it 'should be valid if on list' do
      subject.given_name = 'John'
      subject.family_name = 'Doe'
      subject.name_sfx = 'Jr.'
      expect(subject).to be_valid
    end
  end
end
