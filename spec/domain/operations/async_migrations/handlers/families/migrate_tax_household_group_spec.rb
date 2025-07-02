# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Handlers::Families::MigrateTaxHouseholdGroup, dbclean: :after_each do
  include Dry::Monads[:do, :result]

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true, first_name: "main_name") }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member) }
  let(:application) do
    FactoryBot.create(:application,
                      family_id: family.id,
                      aasm_state: "determined",
                      effective_date: (TimeKeeper.date_of_record - 12.days),
                      origin: :migration,
                      generation_reason: :manual)
  end

  let(:eligibility_determination1) { FactoryBot.create(:financial_assistance_eligibility_determination, application: application) }

  let!(:applicant) do
    FactoryBot.create(:applicant,
                      first_name: "app_nmae",
                      application: application,
                      dob: TimeKeeper.date_of_record - 40.years,
                      is_primary_applicant: true,
                      family_member_id: family.family_members[0].id,
                      person_hbx_id: person.hbx_id,
                      addresses: [FactoryBot.build(:financial_assistance_address)],
                      eligibility_determination_id: eligibility_determination1.id)
  end

  let!(:tax_household_group) { FactoryBot.create(:tax_household_group, family: family, application_hbx_id: application.hbx_id) }
  let!(:tax_household_group2) { FactoryBot.create(:tax_household_group, family: family, application_hbx_id: nil) }
  let!(:tax_household_group3) { FactoryBot.create(:tax_household_group, family: family, application_hbx_id: "12345789") }
  let(:subject) { described_class.new }

  describe '#call' do
    context 'when params are valid' do
      let(:params) { { document_id: family.id.to_s } }

      it 'migrates tax household group successfully' do
        expect(family.tax_household_groups.first.application_gid).to be_nil
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        family.reload
        expect(family.tax_household_groups.first.application_gid).to eq(application.to_global_id.to_s)
      end
    end

    context 'when family_id is invalid' do
      let(:params) { { document_id: 'invalid_id' } }

      it 'returns failure' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to eq('family_id is expected in BSON format')
      end
    end

    context 'when family does not have tax household groups' do
      let(:empty_family) { FactoryBot.create(:family, :with_primary_family_member) }
      let(:params) { { document_id: empty_family.id.to_s } }

      it 'returns success with no changes' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Result::Success)
      end
    end
  end
end