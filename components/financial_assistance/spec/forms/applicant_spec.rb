# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Forms::Applicant, type: :model, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) do
    FactoryBot.create(:family, :with_primary_family_member, :person => person)
  end
  let(:application) { FactoryBot.create(:financial_assistance_application, family: family) }
  let(:primary_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application, is_primary_applicant: true) }

  let(:applicant_properties) do
    { "first_name" => "test",
      "middle_name" => "",
      "last_name" => "fm",
      "dob" => "1982-11-11",
      "ssn" => "",
      "no_ssn" => "1",
      "gender" => "male",
      "tribal_id" => "",
      "ethnicity" => ["", "", "", "", "", "", ""],
      "is_consumer_role" => "true",
      "same_with_primary" => "true",
      "is_homeless" => "false",
      "is_temporarily_out_of_state" => "false",
      "application_id" => application.id,
      "addresses" =>
        { "0" => {"kind" => "home", "address_1" => "", "address_2" => "", "city" => "", "state" => "", "zip" => ""},
          "1" => {"kind" => "mailing", "address_1" => "", "address_2" => "", "city" => "", "state" => "", "zip" => ""}}}
  end

  subject { described_class.new(applicant_properties) }

  before do
    allow(application).to receive(:primary_applicant).and_return(primary_applicant)
    allow(FinancialAssistance::Application).to receive(:find).with(application.id).and_return(application)
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:first_name) }
    it { is_expected.to validate_presence_of(:last_name) }
    it { is_expected.to validate_presence_of(:gender) }
    it { is_expected.to validate_presence_of(:dob) }

    context "when ssn is provided" do
      it "validates length" do
        subject.ssn = "12345"
        expect(subject).not_to be_valid
        expect(subject.errors[:ssn]).to include(" must be 9 digits")
      end
    end

    describe "#check_same_ssn" do
      let(:ssn) { '123456789' }

      context 'when SSN is blank' do
        it 'returns early without adding errors' do
          subject.ssn = nil
          subject.check_same_ssn
          expect(subject.errors).to be_empty
        end

        it 'returns early with empty string SSN' do
          subject.ssn = ''
          subject.check_same_ssn
          expect(subject.errors).to be_empty
        end
      end

      context 'when applicant exists and has the same SSN' do
        let(:existing_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application, ssn: ssn) }

        before do
          subject.applicant_id = existing_applicant.id
          subject.ssn = ssn
        end

        it 'returns early without adding errors' do
          subject.check_same_ssn
          expect(subject.errors).to be_empty
        end
      end

      context 'when QHP application feature is enabled' do
        before do
          allow(subject).to receive(:qhp_application_feature_enabled?).and_return(true)
          subject.ssn = ssn
          subject.dob = "1999-01-01"
          subject.first_name = 'John'
          subject.last_name = 'Doe'
        end

        context 'when checking ssn_is_taken operation for an existing person' do
          let(:ssn_taken_operation) { instance_double(Operations::People::SsnTaken) }

          before do
            subject.applicant_id = primary_applicant.id
            primary_applicant.update_attributes(family_member_id: application.family.family_members.first.id)
            primary_applicant.family_member.person.update(ssn: ssn, dob: "1999-01-01", first_name: 'John', last_name: 'Doe')
            allow(Operations::People::SsnTaken).to receive(:new).and_return(ssn_taken_operation)
          end

          it 'calls operation with skipped_person when the first name has changed' do
            subject.first_name = "Jojo"
            expect(ssn_taken_operation).to receive(:call).with({
                                                                 dob: subject.dob.to_date,
                                                                 first_name: "Jojo",
                                                                 last_name: subject.last_name,
                                                                 ssn: subject.ssn,
                                                                 skipped_person: primary_applicant.family_member.person.hbx_id
                                                               }).and_return(double(success?: true, success: false))

            subject.check_same_ssn
          end

          it 'calls operation with skipped_person when the last name has changed' do
            subject.last_name = "DoeDoe"
            expect(ssn_taken_operation).to receive(:call).with({
                                                                 dob: subject.dob.to_date,
                                                                 first_name: subject.first_name,
                                                                 last_name: "DoeDoe",
                                                                 ssn: subject.ssn,
                                                                 skipped_person: primary_applicant.family_member.person.hbx_id
                                                               }).and_return(double(success?: true, success: false))

            subject.check_same_ssn
          end

          it 'calls operation with skipped_person when the dob has changed' do
            subject.dob = "1999-01-02"
            expect(ssn_taken_operation).to receive(:call).with({
                                                                 dob: "1999-01-02".to_date,
                                                                 first_name: subject.first_name,
                                                                 last_name: subject.last_name,
                                                                 ssn: subject.ssn,
                                                                 skipped_person: primary_applicant.family_member.person.hbx_id
                                                               }).and_return(double(success?: true, success: false))

            subject.check_same_ssn
          end

          it 'calls operation without skipped_person when nothing has changed' do
            expect(ssn_taken_operation).to receive(:call).with({
                                                                 dob: subject.dob.to_date,
                                                                 first_name: subject.first_name,
                                                                 last_name: subject.last_name,
                                                                 ssn: subject.ssn
                                                               }).and_return(double(success?: true, success: false))

            subject.check_same_ssn
          end

          it 'calls operation without skipped_person when the ssn has changed' do
            subject.ssn = "555443333"
            expect(ssn_taken_operation).to receive(:call).with({
                                                                 dob: subject.dob.to_date,
                                                                 first_name: subject.first_name,
                                                                 last_name: subject.last_name,
                                                                 ssn: "555443333"
                                                               }).and_return(double(success?: true, success: false))

            subject.check_same_ssn
          end
        end

        context 'when ssn_is_taken? returns true' do
          before do
            allow(subject).to receive(:ssn_is_taken?).and_return([true, 'ssn is already taken'])
          end

          it 'returns early without checking application applicants' do
            subject.check_same_ssn
            expect(subject.errors).to be_empty
          end
        end

        context 'when ssn_is_taken? returns false' do
          before do
            allow(subject).to receive(:ssn_is_taken?).and_return([false, nil])
          end

          context 'when no matching applicants exist in application' do
            it 'does not add errors' do
              subject.check_same_ssn
              expect(subject.errors).to be_empty
            end
          end

          context 'when matching applicants exist and applicant_id is present' do
            let!(:other_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application, ssn: ssn) }
            let!(:current_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application, ssn: 'different_ssn') }

            before do
              subject.applicant_id = current_applicant.id
            end

            it 'adds error when other applicants with same SSN exist' do
              subject.check_same_ssn
              expect(subject.errors[:base]).to include('The entered SSN is already taken by another applicant in this application.')
            end
          end

          context 'when matching applicants exist and applicant_id is blank' do
            let!(:existing_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application, ssn: ssn) }

            before do
              subject.applicant_id = nil
            end

            it 'adds error when matching applicants exist' do
              subject.check_same_ssn
              expect(subject.errors[:base]).to include('The entered SSN is already taken by another applicant in this application.')
            end
          end

          context 'when no matching applicants exist in application' do
            before do
              subject.applicant_id = nil
            end

            it 'does not add error when no matching applicants exist' do
              subject.check_same_ssn
              expect(subject.errors).to be_empty
            end
          end
        end

        context 'when applicant is nil and ssn_is_taken? returns false' do
          before do
            subject.applicant_id = nil
            allow(subject).to receive(:ssn_is_taken?).and_return([false, nil])
          end

          it 'calls ssn_is_taken? method with correct values' do
            expect(subject).to receive(:ssn_is_taken?).with({
                                                              dob: subject.dob,
                                                              first_name: subject.first_name,
                                                              last_name: subject.last_name,
                                                              ssn: subject.ssn
                                                            }).and_return([false, nil])

            subject.check_same_ssn
          end
        end
      end

      context 'edge cases' do
        it 'handles case when applicant exists but has nil SSN' do
          existing_applicant = FactoryBot.create(:financial_assistance_applicant, application: application, ssn: nil)
          subject.applicant_id = existing_applicant.id
          subject.ssn = ssn
          allow(subject).to receive(:qhp_application_feature_enabled?).and_return(true)
          allow(subject).to receive(:ssn_is_taken?).and_return([false, nil])

          expect { subject.check_same_ssn }.not_to raise_error
        end
      end
    end
  end

  describe "#has_in_state_home_addresses?" do
    it "validates address within state boundaries" do
      addresses_attrs = {
        "0" => { kind: "home", address_1: "123 Main St", city: "Washington", state: EnrollRegistry[:enroll_app].setting(:state_abbreviation).item, zip: "20001" }
      }

      expect(subject).to receive(:has_in_state_home_addresses?).with(addresses_attrs).and_return(true)
      subject.addresses_attributes = addresses_attrs
      allow(subject).to receive(:valid?).and_return(true)
      allow(subject).to receive(:extract_applicant_params).and_return({})
      subject.save
    end
  end

  describe "#destroy_mailing_address?" do
    it "returns true when conditions are met" do
      address = { kind: "mailing", _destroy: "true", id: "123" }
      expect(subject.destroy_mailing_address?(address)).to be true
    end

    it "returns false when address is not mailing" do
      address = { kind: "home", _destroy: "true", id: "123" }
      expect(subject.destroy_mailing_address?(address)).to be false
    end

    it "returns false when not marked for destruction" do
      address = { kind: "mailing", _destroy: "false", id: "123" }
      expect(subject.destroy_mailing_address?(address)).to be false
    end
  end

  describe "#primary_applicant_address_attributes" do
    let(:home_address) { double(attributes: { "address_1" => "123 Main St", "city" => "DC", "state" => "WA", "zip" => "20001", "kind" => "home" }) }

    before do
      allow(primary_applicant).to receive_message_chain(:addresses, :in, :first).and_return(home_address)
      allow(home_address).to receive(:slice).and_return(home_address.attributes)
    end

    it "copies primary applicant's address" do
      subject.is_dependent = "true"
      subject.same_with_primary = "true"
      expect(subject.primary_applicant_address_attributes).to be_a(Hash)
    end
  end

  context 'when age_off_excluded is true ' do
    subject { FinancialAssistance::Forms::Applicant.new(applicant_properties.merge({age_off_excluded: "true"})) }

    it "should return true" do
      expect(subject.age_off_excluded).to eq "true"
    end
  end

  context 'when us_citizen is false and immigration_status_question is not required' do
    before do
      allow(EnrollRegistry[:immigration_status_question_required].feature).to receive(:is_enabled).and_return(false)
    end

    subject { FinancialAssistance::Forms::Applicant.new(applicant_properties.merge({"us_citizen" => "false", "indian_tribe_member" => "false", "is_incarcerated" => "false"})) }

    it "should return false" do
      subject.eligible_immigration_status = ""
      expect(subject.eligible_immigration_status).to eq false
    end
  end

  context 'when us_citizen is nil and immigration_status_question is not required' do
    before do
      allow(EnrollRegistry[:immigration_status_question_required].feature).to receive(:is_enabled).and_return(false)
    end

    subject { FinancialAssistance::Forms::Applicant.new(applicant_properties.merge({"us_citizen" => nil, "indian_tribe_member" => "false", "is_incarcerated" => "false"})) }

    it "should return nil" do
      subject.eligible_immigration_status = ""
      expect(subject.eligible_immigration_status).to eq nil
    end
  end

  context 'when us_citizen is false and immigration_status_question is required' do
    before do
      allow(EnrollRegistry[:immigration_status_question_required].feature).to receive(:is_enabled).and_return(true)
    end

    subject { FinancialAssistance::Forms::Applicant.new(applicant_properties.merge({"us_citizen" => "false", "indian_tribe_member" => "false", "is_incarcerated" => "false"})) }

    it "should return nil" do
      subject.eligible_immigration_status = ""
      expect(subject.eligible_immigration_status).to eq nil
    end
  end
end
