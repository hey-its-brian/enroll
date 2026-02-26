# frozen_string_literal: true

require 'rails_helper'

describe Email, :dbclean => :after_each do
  let!(:person) {FactoryBot.create(:person, gender: "male", dob: "10/10/1974", ssn: "123456789")}
  let(:valid_params) do
    {
      kind: "home",
      address: "test@test.com",
      person: person
    }
  end

  describe 'validations' do
    it { should validate_presence_of :address }
    it { should validate_presence_of :kind }

    describe 'email type' do

      context 'when empty' do
        let(:params){valid_params.deep_merge({kind: ""})}
        it 'is invalid' do
          expect(Email.create(**params).errors[:kind].any?).to be_truthy
          expect(Email.create(**params).errors[:kind]).to eq ["Choose a type", " is not a valid email type"]
        end
      end

      context "when invalid" do
        let(:params){valid_params.deep_merge(kind: "fake")}
        it 'is invalid' do
          expect(Email.create(**params).errors[:kind].any?).to be_truthy
          expect(Email.create(**params).errors[:kind]).to eq ["fake is not a valid email type"]
        end
      end

      context "invalid address" do

        let(:params){valid_params.deep_merge(address: "test@test")}

        it "is invalid" do
          record = Email.create(**params)
          expect(record.errors[:address]).to be_truthy
          expect(record.errors[:address]).to include("should be a valid email address")
        end
      end

      context "valid address" do
        let(:email) {"test@test.com"}
        let(:params){valid_params.deep_merge(address: email)}

        it "is valid" do
          Email.create(params)
          person.reload
          expect(person.emails.where(address: email).first.valid?).to be_truthy
        end
      end

      valid_types = Email::KINDS
      valid_types.each do |type|
        context("when valid #{type} address") do
          let(:params){valid_params.deep_merge({kind: type, address: "#{type}@#{type}.com"})}
          it 'is valid' do
            record = Email.create(**params)
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
          record = Email.create(**params)
          expect(record.errors[:address].any?).to be_truthy
          expect(record.errors[:address]).to include("can't be blank")
        end
      end

      context "when invalid" do
        let(:params){valid_params.deep_merge({address: "test@test"})}
        it "should give an error" do
          record = Email.create(**params)
          expect(record.errors[:address].any?).to be_truthy
          expect(record.errors[:address]).to include("should be a valid email address")
        end
      end

      context "when adding already email present" do
        let(:params) {valid_params}
        it "should not throw an error" do
          expect(Email.create(**params).valid?).to be_truthy
        end
      end

      context "email format validation" do
        context "with valid email formats" do
          [
            "user@example.com",
            "user.name@example.com",
            "user+tag@example.co.uk",
            "user_name@example.com",
            "user-name@example.com",
            "user123!@example123.com",
            "123@example.com",
            "a@b.co",
            "user@subdomain.example.com",
            "user@example-domain.com"
          ].each do |valid_email|
            it "accepts #{valid_email}" do
              params = valid_params.merge(address: valid_email)
              record = Email.create(**params)
              expect(record.errors[:address]).to be_empty
            end
          end
        end

        context "with invalid email formats" do
          [
            "user@",
            "@example.com",
            "user @example.com",
            "user@example .com",
            "user@.example.com",
            "user@example..com",
            "user@example.com.",
            "user@-example.com",
            "user@example-.com",
            "user name@example.com",
            "user@exam ple.com",
            "user()@example.com",
            "user[]@example.com",
            "user,@example.com",
            "user;@example.com",
            "user:@example.com",
            "user<>@example.com",
            "plaintext",
            "user@@example.com",
            "user@example@com"
          ].each do |invalid_email|
            it "rejects #{invalid_email}" do
              params = valid_params.merge(address: invalid_email)
              record = Email.create(**params)
              expect(record.errors[:address]).to include("should be a valid email address")
            end
          end
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
    let(:email) { Email.create(**params)}

    context 'emails are the same' do
      let(:other_email) { email.clone }
      it 'returns true' do
        expect(email.match(other_email)).to be_truthy
      end
    end

    context 'emails differ' do
      context 'by type' do
        let(:other_email) do
          e = email.clone
          e.kind = 'work'
          e
        end
        it 'returns false' do
          expect(email.match(other_email)).to be false
        end
      end

      context 'by address' do
        let(:other_email) do
          e = email.clone
          e.address = 'something@different.com'
          e
        end
        it 'returns false' do
          expect(email.match(other_email)).to be false
        end
      end
    end
  end
end
