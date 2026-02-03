# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::FinancialAssistance::Forms::Applicant, type: :model, dbclean: :after_each do
  let!(:application) do
    FactoryBot.create(:application,
                      family_id: BSON::ObjectId.new,
                      aasm_state: 'draft',
                      effective_date: Date.today)
  end

  let!(:applicant) do
    FactoryBot.create(:applicant,
                      :with_basic_info,
                      :with_ssn,
                      application: application,
                      is_applying_coverage: true,
                      is_incarcerated: false,
                      indian_tribe_member: false,
                      us_citizen: true,
                      dob: Date.today - 40.years,
                      is_primary_applicant: true,
                      family_member_id: BSON::ObjectId.new)
  end

  let!(:spouse_applicant) do
    appl = FactoryBot.create(:applicant,
                             application: application,
                             dob: Date.today - 40.years,
                             family_member_id: BSON::ObjectId.new)
    application.ensure_relationship_with_primary(appl, 'spouse')
    appl
  end

  let(:params) do
    { first_name: input_applicant.first_name,
      last_name: input_applicant.last_name,
      middle_name: '',
      name_sfx: '',
      dob: input_applicant.dob.strftime("%Y-%m-%d"),
      ssn: input_applicant.ssn,
      gender: input_applicant.gender,
      is_applying_coverage: 'true',
      us_citizen: 'true',
      naturalized_citizen: 'false',
      indian_tribe_member: 'false',
      tribal_id: '',
      is_incarcerated: 'false',
      relationship: relationship,
      is_consumer_role: 'true',
      is_temporarily_out_of_state: '0',
      is_homeless: '0',
      no_ssn: '0',
      addresses_attributes: { :'0' => { kind: 'home',
                                        address_1: '',
                                        address_2: '',
                                        city: '',
                                        state: '',
                                        zip: '',
                                        _destroy: 'false'},
                              :'1' => { kind: 'mailing',
                                        address_1: '',
                                        address_2: '',
                                        city: '',
                                        state: '',
                                        zip: '',
                                        _destroy: 'false'}},
      ethnicity: ['', '', '', '', '', '', '']}
  end

  context 'relationship_validation' do

    before do
      @applicant_form = described_class.new(params)
      @applicant_form.application_id = application.id
      @applicant_form.applicant_id = input_applicant.id
      @applicant_form.relationship_validation
    end

    context 'applicant spouse update' do
      let(:input_applicant) {spouse_applicant}
      let(:relationship) {'spouse'}

      it 'should not add any errors when checked for validation errors' do
        expect(@applicant_form.errors.full_messages).to be_empty
      end
    end

    context 'with spouse and child as spouse' do
      let!(:child_applicant) do
        appl = FactoryBot.create(:applicant,
                                 application: application,
                                 dob: Date.today - 40.years,
                                 family_member_id: BSON::ObjectId.new)
        application.ensure_relationship_with_primary(appl, 'child')
        appl
      end

      let(:input_applicant) {child_applicant}
      let(:relationship) {'spouse'}

      it 'should add error when checked for validation errors' do
        expect(@applicant_form.errors.full_messages).to include('can not have multiple spouse or life partner')
      end
    end

    context 'with more than one spouse' do
      let!(:spouse_applicant2) do
        appl = FactoryBot.create(:applicant,
                                 application: application,
                                 dob: Date.today - 40.years,
                                 family_member_id: BSON::ObjectId.new)
        application.ensure_relationship_with_primary(appl, 'spouse')
        appl
      end

      let(:input_applicant) {spouse_applicant2}
      let(:relationship) {'spouse'}

      it 'should add error when checked for validation errors' do
        expect(@applicant_form.errors.full_messages).to include('can not have multiple spouse or life partner')
      end
    end
  end

  describe "ssn is missing" do
    let!(:application2) { FactoryBot.create(:financial_assistance_application, family_id: BSON::ObjectId.new) }
    let!(:other_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application2, ssn: '889984400', family_member_id: BSON::ObjectId.new, is_primary_applicant: true) }
    let!(:child_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application, dob: Date.today - 40.years, family_member_id: BSON::ObjectId.new) }
    let(:input_applicant) {child_applicant}
    let(:relationship) {'child'}
    before do
      allow_any_instance_of(described_class).to receive(:relationship_validation).and_return(nil)
      @applicant_form = described_class.new(params.merge!(first_name: "Test", last_name: "User", gender: "male", same_with_primary: false))
      @applicant_form.save
    end

    it "form should contain error" do
      expect(@applicant_form.errors.full_messages.first).to include(l10n("ssn_or_no_ssn_not_provided"))
    end
  end


  context 'check_same_ssn' do
    context 'applicant child update with same ssn' do
      let!(:application2) { FactoryBot.create(:financial_assistance_application, family_id: BSON::ObjectId.new) }
      let!(:other_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application2, ssn: '889984400', family_member_id: BSON::ObjectId.new) }
      let!(:child_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application, dob: Date.today - 40.years, family_member_id: BSON::ObjectId.new) }

      before do
        @applicant_form = described_class.new(params.except(:ssn).merge({ssn: '889984400'}))
        @applicant_form.application_id = application.id
        @applicant_form.applicant_id = input_applicant.id
        @applicant_form.relationship_validation
        @applicant_form.check_same_ssn
      end

      let(:input_applicant) {child_applicant}
      let(:relationship) {'child'}

      it 'should add error when ssn is matching' do
        error_text = l10n('insured.consumer_roles.ssn_already_taken_error', contact_center_phone_number: EnrollRegistry[:enroll_app].settings(:contact_center_full_number).item)
        expect(@applicant_form.errors.full_messages).to include(error_text)
      end
    end

    context 'when single applicant in the application' do
      let!(:application2) { FactoryBot.create(:financial_assistance_application, family_id: BSON::ObjectId.new) }
      let!(:other_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application2, ssn: '889984400', family_member_id: BSON::ObjectId.new, dob: Date.today - 40.years) }

      let(:params2) do
        { first_name: other_applicant.first_name,
          last_name: other_applicant.last_name,
          middle_name: '',
          name_sfx: '',
          dob: other_applicant.dob.strftime("%Y-%m-%d"),
          ssn: other_applicant.ssn,
          gender: other_applicant.gender,
          is_applying_coverage: 'true',
          us_citizen: 'true',
          naturalized_citizen: 'false',
          indian_tribe_member: 'false',
          tribal_id: '',
          is_incarcerated: 'false',
          relationship: "self",
          is_consumer_role: 'true',
          is_temporarily_out_of_state: '0',
          is_homeless: '0',
          no_ssn: '0',
          addresses_attributes: { :'0' => { kind: 'home',
                                            address_1: '',
                                            address_2: '',
                                            city: '',
                                            state: '',
                                            zip: '',
                                            _destroy: 'false'},
                                  :'1' => { kind: 'mailing',
                                            address_1: '',
                                            address_2: '',
                                            city: '',
                                            state: '',
                                            zip: '',
                                            _destroy: 'false'}},
          ethnicity: ['', '', '', '', '', '', '']}
      end

      before do
        @applicant_form = described_class.new(params2)
        @applicant_form.application_id = application2.id
        @applicant_form.applicant_id = other_applicant.id
        @applicant_form.check_same_ssn
      end

      it 'should not throw 502 error' do
        expect(@applicant_form.errors.full_messages.present?).to be_falsey
      end
    end
  end

  context 'validate_in_state_addresses' do
    let!(:application2) { FactoryBot.create(:financial_assistance_application, family_id: BSON::ObjectId.new) }
    let!(:other_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application2, ssn: '889984400', dob: Date.today - 40.years, family_member_id: BSON::ObjectId.new) }

    context 'applicant with home addresses' do
      let(:params2) do
        { first_name: other_applicant.first_name,
          last_name: other_applicant.last_name,
          middle_name: '',
          name_sfx: '',
          dob: other_applicant.dob.strftime("%Y-%m-%d"),
          ssn: other_applicant.ssn,
          gender: other_applicant.gender,
          is_applying_coverage: 'true',
          us_citizen: 'true',
          naturalized_citizen: 'false',
          indian_tribe_member: 'false',
          tribal_id: '',
          is_incarcerated: 'false',
          relationship: "self",
          is_consumer_role: 'true',
          is_temporarily_out_of_state: '0',
          is_homeless: '0',
          no_ssn: '0',
          addresses_attributes: { :'0' => { kind: 'home',
                                            address_1: '',
                                            address_2: '',
                                            city: '',
                                            state: EnrollRegistry[:enroll_app].setting(:state_abbreviation).item,
                                            zip: '',
                                            _destroy: 'false'},
                                  :'1' => { kind: 'mailing',
                                            address_1: '',
                                            address_2: '',
                                            city: '',
                                            state: EnrollRegistry[:enroll_app].setting(:state_abbreviation).item,
                                            zip: '',
                                            _destroy: 'false'}},
          ethnicity: ['', '', '', '', '', '', '']}
      end

      before do
        @applicant_form = described_class.new(params2)
        @applicant_form.application_id = application2.id
        @applicant_form.applicant_id = other_applicant.id
      end

      it 'should return true' do
        expect(@applicant_form.has_in_state_home_addresses?(params2[:addresses_attributes])).to be_truthy
      end
    end

    context 'applicant with only mailing addresses' do
      let(:params2) do
        { first_name: other_applicant.first_name,
          last_name: other_applicant.last_name,
          middle_name: '',
          name_sfx: '',
          dob: other_applicant.dob.strftime("%Y-%m-%d"),
          ssn: other_applicant.ssn,
          gender: other_applicant.gender,
          is_applying_coverage: 'true',
          us_citizen: 'true',
          naturalized_citizen: 'false',
          indian_tribe_member: 'false',
          tribal_id: '',
          is_incarcerated: 'false',
          relationship: "self",
          is_consumer_role: 'true',
          is_temporarily_out_of_state: '0',
          is_homeless: '0',
          no_ssn: '0',
          addresses_attributes: { :'0' => { kind: 'mailing',
                                            address_1: '',
                                            address_2: '',
                                            city: '',
                                            state: EnrollRegistry[:enroll_app].setting(:state_abbreviation).item,
                                            zip: '',
                                            _destroy: 'false'}},
          ethnicity: ['', '', '', '', '', '', '']}
      end

      before do
        @applicant_form = described_class.new(params2)
        @applicant_form.application_id = application2.id
        @applicant_form.applicant_id = other_applicant.id
      end

      it 'should return false' do
        expect(@applicant_form.has_in_state_home_addresses?(params2[:addresses_attributes])).to be_falsey
      end
    end

    context 'applicant with no addresses' do
      let(:params2) do
        { first_name: other_applicant.first_name,
          last_name: other_applicant.last_name,
          middle_name: '',
          name_sfx: '',
          dob: other_applicant.dob.strftime("%Y-%m-%d"),
          ssn: other_applicant.ssn,
          gender: other_applicant.gender,
          is_applying_coverage: 'true',
          us_citizen: 'true',
          naturalized_citizen: 'false',
          indian_tribe_member: 'false',
          tribal_id: '',
          is_incarcerated: 'false',
          relationship: "self",
          is_consumer_role: 'true',
          is_temporarily_out_of_state: '0',
          is_homeless: '0',
          no_ssn: '0',
          ethnicity: ['', '', '', '', '', '', '']}
      end

      before do
        @applicant_form = described_class.new(params2)
        @applicant_form.application_id = application2.id
        @applicant_form.applicant_id = other_applicant.id
      end

      it 'should return false' do
        expect(@applicant_form.has_in_state_home_addresses?(params2[:addresses_attributes])).to be_falsey
      end
    end

    context 'applicant with outside state addresses' do
      let(:params2) do
        { first_name: other_applicant.first_name,
          last_name: other_applicant.last_name,
          middle_name: '',
          name_sfx: '',
          dob: other_applicant.dob.strftime("%Y-%m-%d"),
          ssn: other_applicant.ssn,
          gender: other_applicant.gender,
          is_applying_coverage: 'true',
          us_citizen: 'true',
          naturalized_citizen: 'false',
          indian_tribe_member: 'false',
          tribal_id: '',
          is_incarcerated: 'false',
          relationship: "self",
          is_consumer_role: 'true',
          is_temporarily_out_of_state: '0',
          is_homeless: '0',
          no_ssn: '0',
          addresses_attributes: { :'0' => { kind: 'home',
                                            address_1: '',
                                            address_2: '',
                                            city: '',
                                            state: 'VA',
                                            zip: '',
                                            _destroy: 'false'}},
          ethnicity: ['', '', '', '', '', '', '']}
      end

      before do
        @applicant_form = described_class.new(params2)
        @applicant_form.application_id = application2.id
        @applicant_form.applicant_id = other_applicant.id
      end

      it 'should return false' do
        expect(@applicant_form.has_in_state_home_addresses?(params2[:addresses_attributes])).to be_falsey
      end
    end
  end

  context 'applicant without home addresses and same_with_primary as true' do
    let(:params2) do
      { same_with_primary: "true",
        first_name: "test",
        last_name: "test",
        middle_name: '',
        name_sfx: '',
        dob: (TimeKeeper.date_of_record - 20.years).strftime("%Y-%m-%d"),
        ssn: "123152356",
        gender: "male",
        is_applying_coverage: 'true',
        us_citizen: 'true',
        naturalized_citizen: 'false',
        indian_tribe_member: 'false',
        tribal_id: '',
        is_incarcerated: 'false',
        relationship: "self",
        is_consumer_role: 'true',
        is_temporarily_out_of_state: '0',
        is_homeless: '0',
        no_ssn: '0',
        addresses_attributes: { :'0' => { kind: 'home',
                                          address_1: '',
                                          address_2: '',
                                          city: '',
                                          state: '',
                                          zip: '',
                                          _destroy: 'false'}},
        ethnicity: ['', '', '', '', '', '', '']}
    end

    before do
      applicant.addresses << FinancialAssistance::Locations::Address.new({kind: 'home', city: 'Bar Harbor', county: 'Cumberland', state: 'ME', zip: '04401', address_1: '1600 Main St'})
      @applicant_form = described_class.new(params2)
      @applicant_form.application_id = application.id
      @applicant_form.applicant_id = spouse_applicant.id
      @applicant_form.is_dependent = "true"
      @applicant_form.save
    end

    it 'should return true' do
      spouse_applicant.reload
      expect(spouse_applicant.addresses.first.present?).to be_truthy
    end
  end

  describe '#save' do
    context '' do
      let(:input_applicant) { applicant }
      let(:params) do
        {
          first_name: input_applicant.first_name,
          last_name: input_applicant.last_name,
          middle_name: '',
          name_sfx: '',
          dob: input_applicant.dob.strftime("%Y-%m-%d"),
          ssn: input_applicant.ssn,
          gender: input_applicant.gender,
          is_applying_coverage: input_applicant.is_applying_coverage,
          us_citizen: input_applicant.us_citizen,
          naturalized_citizen: input_applicant.naturalized_citizen,
          indian_tribe_member: input_applicant.indian_tribe_member,
          tribal_id: '',
          is_incarcerated: input_applicant.is_incarcerated,
          relationship: 'self',
          is_consumer_role: 'true',
          is_temporarily_out_of_state: '0',
          is_homeless: '0',
          no_ssn: '0',
          addresses_attributes: addresses_information,
          ethnicity: ['', '', '', '', '', '', '']
        }
      end

      let(:addresses_information) do
        addresses_params = {}
        applicant.addresses.each_with_index do |address, index|
          addresses_params[index.to_s] = {
            id: address.id,
            kind: address.kind,
            address_1: address.address_1,
            address_2: address.address_2,
            city: address.city,
            state: address.state,
            zip: address.zip,
            _destroy: address.mailing?.to_s
          }
        end
        addresses_params
      end

      before do
        applicant.addresses.create!(
          {
            kind: 'home',
            address_1: '123 Main St Home',
            city: 'Bar Harbor',
            state: 'ME',
            zip: '04401',
            county: 'Cumberland'
          }
        )
        applicant.addresses.create!(
          {
            kind: 'mailing',
            address_1: '123 Main St Mailing',
            city: 'Bar Harbor',
            state: 'ME',
            zip: '04401',
            county: 'Cumberland'
          }
        )
      end

      it 'destroys the mailing address of the applicant' do
        expect(applicant.addresses.where(kind: 'mailing').first).to be_a(FinancialAssistance::Locations::Address)
        applicant_form = described_class.new(params)
        applicant_form.application_id = application.id
        applicant_form.applicant_id = input_applicant.id
        applicant_form.save
        expect(applicant_form.errors.full_messages).to be_empty
        expect(applicant.reload.addresses.where(kind: 'mailing').first).to be_nil
      end
    end
  end

  describe "#vlp_parameters" do
    let(:input_applicant) { applicant }
    let(:relationship) { nil }
    let(:applicant_form) { described_class.new(params) }

    before do
      applicant_form.application_id = application.id
      applicant_form.applicant_id = input_applicant.id
    end

    context "when all VLP attributes are blank" do
      it "returns only country_of_citizenship even when nil" do
        expect(applicant_form.vlp_parameters).to eq({ country_of_citizenship: nil })
      end
    end

    context "when country_of_citizenship is present" do
      before do
        allow(applicant_form).to receive(:country_of_citizenship).and_return("US")
      end

      it "includes country_of_citizenship even if blank" do
        allow(applicant_form).to receive(:country_of_citizenship).and_return("")
        result = applicant_form.vlp_parameters
        expect(result).to have_key(:country_of_citizenship)
        expect(result[:country_of_citizenship]).to eq("")
      end

      it "includes country_of_citizenship when present" do
        result = applicant_form.vlp_parameters
        expect(result).to eq({ country_of_citizenship: "US" })
      end
    end

    context "when other VLP attributes are present" do
      before do
        allow(applicant_form).to receive(:alien_number).and_return("123456789")
        allow(applicant_form).to receive(:i94_number).and_return("I94123456")
        allow(applicant_form).to receive(:visa_number).and_return("VISA123")
        allow(applicant_form).to receive(:passport_number).and_return("PASS123456")
        allow(applicant_form).to receive(:sevis_id).and_return("SEVIS123")
        allow(applicant_form).to receive(:naturalization_number).and_return("NAT123456")
        allow(applicant_form).to receive(:receipt_number).and_return("REC123456")
        allow(applicant_form).to receive(:citizenship_number).and_return("CIT123456")
        allow(applicant_form).to receive(:card_number).and_return("CARD123456")
        allow(applicant_form).to receive(:expiration_date).and_return("2025-12-31")
        allow(applicant_form).to receive(:issuing_country).and_return("US")
        allow(applicant_form).to receive(:status).and_return("Valid")
        allow(applicant_form).to receive(:vlp_description).and_return("Test description")
      end

      it "includes all present VLP attributes" do
        result = applicant_form.vlp_parameters
        expect(result).to include(
          alien_number: "123456789",
          i94_number: "I94123456",
          visa_number: "VISA123",
          passport_number: "PASS123456",
          sevis_id: "SEVIS123",
          naturalization_number: "NAT123456",
          receipt_number: "REC123456",
          citizenship_number: "CIT123456",
          card_number: "CARD123456",
          expiration_date: "2025-12-31",
          issuing_country: "US",
          status: "Valid",
          vlp_description: "Test description"
        )
      end
    end
  end
end
