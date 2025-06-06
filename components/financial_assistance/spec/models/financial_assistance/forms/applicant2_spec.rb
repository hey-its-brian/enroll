# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Forms::Applicant, type: :model, dbclean: :after_each do
  before :all do
    DatabaseCleaner.clean
  end

  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:application) { FactoryBot.create(:financial_assistance_application, family: family) }
  let(:primary_ssn) { '888888888' }
  let(:primary_applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      application: application,
      is_primary_applicant: true,
      family_member_id: family.primary_applicant.id,
      person_hbx_id: person.hbx_id,
      ssn: primary_ssn
    )
  end
  let(:dependent_ssn) { '999999999'}
  let(:dependent) do
    per = FactoryBot.create(:person, :with_consumer_role, ssn: '999999999')
    person.ensure_relationship_with(per, 'spouse')
    per
  end
  let(:dependent_params) do
    {
      'first_name' => dependent.first_name,
      'middle_name' => '',
      'last_name' => dependent.last_name,
      'dob' => input_dob,
      'ssn' => dependent_ssn,
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
  let(:input_dob) { dependent.dob.strftime('%Y-%m-%d') }
  let(:dependent_applicant_id) { nil }

  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
  end

  let(:applicant_form) do
    form_obj = described_class.new(dependent_params)
    form_obj.application_id = primary_applicant.application.id
    form_obj.applicant_id = dependent_applicant_id
    form_obj.is_dependent = true
    form_obj
  end

  describe '.new' do
    describe 'validations' do
      describe 'validation: ssn_is_taken?' do
        context 'when a person exists with:
          - same ssn
          - same dob
          - same first_name
          - same last_name
          ' do

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

      describe 'validation: check_same_ssn' do
        context 'when a new applicant is being added with the same ssn as an existing applicant' do
          let(:dependent_ssn) { primary_ssn }

          it 'returns false with errors' do
            expect(applicant_form.save[0]).to be_falsey
            expect(applicant_form.errors.full_messages).to include(
              'Same SSN is already taken by another applicant in this application.'
            )
          end
        end

        context 'when an existing applicant is being updated with the same ssn as an existing applicant' do
          let(:dependent_ssn) { primary_ssn }
          let(:dependent_applicant_id) { dependent_applicant.id }
          let(:dependent_member) { FactoryBot.create(:family_member, family: family, person: dependent) }
          let(:dependent_applicant) do
            FactoryBot.create(
              :financial_assistance_applicant,
              application: application,
              first_name: dependent.first_name,
              last_name: dependent.last_name,
              dob: dependent.dob,
              ssn: dependent.ssn,
              is_primary_applicant: false,
              family_member_id: dependent_member.id,
              person_hbx_id: dependent.hbx_id
            )
          end

          it 'returns false with errors' do
            expect(applicant_form.save[0]).to be_falsey
            expect(applicant_form.errors.full_messages).to include(
              'Same SSN is already taken by another applicant in this application.'
            )
          end
        end
      end
    end
  end
end
