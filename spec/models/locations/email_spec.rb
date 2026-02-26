# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Locations::Email, type: :model do
  before :all do
    DatabaseCleaner.clean
  end

  let(:applicant) { FactoryBot.create(:individual_market_applicant) }
  let(:email) { FactoryBot.create(:location_email, emailable: applicant) }
  let(:valid_params) do
    {
      kind: "home",
      address: "test@test.com",
      emailable: applicant
    }
  end

  subject { Locations::Email }

  describe 'associations' do
    it 'is embedded in the emailable' do
      expect(email).to be_a(Locations::Email)
      expect(email.emailable).to eq(applicant)
    end
  end

  describe 'validations' do
    it { should validate_presence_of :address }
    it { should validate_presence_of :kind }

    describe 'email type' do

      context 'when empty' do
        let(:params){valid_params.deep_merge({kind: ""})}
        it 'is invalid' do
          expect(subject.create(**params).errors[:kind].any?).to be_truthy
          expect(subject.create(**params).errors[:kind]).to eq ["Choose a type", " is not a valid email type"]
        end
      end

      context "when invalid" do
        let(:params){valid_params.deep_merge(kind: "fake")}
        it 'is invalid' do
          expect(subject.create(**params).errors[:kind].any?).to be_truthy
          expect(subject.create(**params).errors[:kind]).to eq ["fake is not a valid email type"]
        end
      end

      context "invalid address" do
        let(:params){valid_params.deep_merge(address: "test@test")}

        it "is invalid" do
          expect(subject.create(**params).errors[:address]).to be_truthy
          expect(subject.create(**params).errors[:address]).to include("should be a valid email address")
        end
      end

      context "valid address" do
        let(:email) {"test@test.com"}
        let(:params){valid_params.deep_merge(address: email)}

        it "is valid" do
          subject.create(params)
          applicant.reload
          expect(applicant.emails.where(address: email).first.valid?).to be_truthy
        end
      end

      valid_types = Locations::Email::KINDS
      valid_types.each do |type|
        context("when valid #{type} address") do
          let(:params){valid_params}
          it 'is valid' do
            params.deep_merge!({kind: type, address: "#{type}@#{type}.com"})
            record = subject.create(**params)
            expect(record).to be_truthy
            expect(record.errors.messages.size).to eq 0
          end
        end
      end
    end

    describe "address" do

      context "when empty" do
        let(:params){valid_params.deep_merge({address: ""})}
        it "should give an error" do
          record = subject.create(**params)
          expect(record.errors[:address].any?).to be_truthy
          expect(record.errors[:address]).to include("can't be blank")
        end
      end

      context "when invalid" do
        let(:params){valid_params.deep_merge({address: "something invalid"})}
        it "should give an error" do
          record = subject.create(**params)
          expect(record.errors[:address].any?).to be_truthy
          expect(record.errors[:address]).to include("should be a valid email address")
        end
      end

      context "when adding already email present" do
        let(:params) {valid_params}
        it "should not throw an error" do
          expect(subject.create(**params).valid?).to be_truthy
        end
      end
    end

    describe 'presence' do
      [:address].each do |missing|
        it("is invalid without #{missing}") do
          trait = "without_email_#{missing}"
          email = FactoryBot.build(:email, trait.to_sym)
          expect(email).to be_invalid
        end
      end
    end
  end

  describe '#match' do
    let(:params){valid_params}
    let(:email) { subject.create(**params)}

    context 'emails are the same' do
      let(:other_email) { email.clone }
      it 'returns true' do
        expect(email.match(other_email)).to be_truthy
      end
    end

    context 'emails differ' do
      context 'by type' do
        let(:other_email) do
          o_email = email.clone
          o_email.kind = 'work'
          o_email
        end
        it 'returns false' do
          expect(email.match(other_email)).to be false
        end
      end

      context 'by address' do
        let(:other_email) do
          o_email = email.clone
          o_email.address = 'something@different.com'
          o_email
        end
        it 'returns false' do
          expect(email.match(other_email)).to be false
        end
      end
    end
  end
end