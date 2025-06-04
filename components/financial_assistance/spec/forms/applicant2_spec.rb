# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Forms::Applicant, type: :model, dbclean: :after_each do
  before :all do
    DatabaseCleaner.clean
  end

  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:application) { FactoryBot.create(:financial_assistance_application, family: family) }
  let(:primary_applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      application: application,
      is_primary_applicant: true,
      family_member_id: family.primary_applicant.id,
      person_hbx_id: person.hbx_id
    )
  end

  let(:dependent_params) do
    {
      'first_name' => dependent.first_name,
      'middle_name' => '',
      'last_name' => dependent.last_name,
      'dob' => input_dob,
      'ssn' => '999999999',
      'no_ssn' => '1',
      'gender' => 'male',
      'tribal_id' => '',
      'ethnicity' => ['', '', '', '', '', '', ''],
      'is_consumer_role' => 'true',
      'same_with_primary' => 'true',
      'is_homeless' => 'false',
      'is_temporarily_out_of_state' => 'false',
      'application_id' => application.id,
      'relationship' => 'child',
      'us_citizen' => 'true',
      'naturalized_citizen' => 'false',
      'indian_tribe_member' => 'false',
      'is_incarcerated' => 'false',
      'addresses_attributes' => {
        '0' => {'kind' => 'home', 'address_1' => '', 'address_2' => '', 'city' => '', 'state' => '', 'zip' => ''},
        '1' => {'kind' => 'mailing', 'address_1' => '', 'address_2' => '', 'city' => '', 'state' => '', 'zip' => ''}
      }
    }
  end

  let(:dependent) { FactoryBot.create(:person, :with_consumer_role, ssn: '999999999') }

  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
  end

  let(:applicant_form) do
    form_obj = described_class.new(dependent_params)
    form_obj.application_id = primary_applicant.application.id
    form_obj.is_dependent = true
    form_obj
  end

  describe '.new' do
    context 'when a person exists with:
      - same ssn
      - same dob
      - same first_name
      - same last_name
      ' do
      let(:input_dob) { dependent.dob.strftime('%Y-%m-%d') }

      it 'returns true without any errors' do
        expect(applicant_form.save[0]).to be_truthy
        expect(applicant_form.errors.full_messages).to be_empty
      end
    end

    context 'when a person exists with:
      - same ssn
      - different dob
      - same first_name
      - same last_name
      ' do
      let(:input_dob) { (TimeKeeper.date_of_record - 10.years).strftime('%Y-%m-%d') }

      it 'returns false with errors' do
        expect(applicant_form.save[0]).to be_falsey
        expect(applicant_form.errors.full_messages).to include('SSN is already taken.')
      end
    end
  end
end
