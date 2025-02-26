# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::Families::HireAssisterAgency, dbclean: :after_each do

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :male, first_name: 'john', last_name: 'adams', dob: 40.years.ago, ssn: '472743442') }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person)}
  let(:assister_agency_profile) { FactoryBot.build(:benefit_sponsors_organizations_assister_agency_profile)}
  let(:writing_agent)         { FactoryBot.create(:assister_role, benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id) }
  let(:assister)  do
    assister = FactoryBot.build(:assister_role, benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id, npn: "SMECDOA00")
    assister.save(validate: false)
    assister
  end
  let(:assister_agency_profile2) { FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile)}
  let(:writing_agent2)         { FactoryBot.create(:assister_role, benefit_sponsors_assister_agency_profile_id: assister_agency_profile2.id) }

  describe 'assister agency account hire params for family' do
    context 'when valid params passed' do
      it 'should create assister agency for family' do
        hire_params = { family_id: family.id,
                        terminate_date: TimeKeeper.date_of_record,
                        assister_role_id: writing_agent.id,
                        start_date: DateTime.now,
                        current_assister_account_id: family&.current_assister_agency&.id }

        result = subject.call(hire_params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq true
        family.reload
        expect(family.current_assister_agency.writing_agent).to eq writing_agent
      end
    end

    context 'rehiring same active assister' do
      before(:each) do
        family.assister_agency_accounts << BenefitSponsors::Accounts::AssisterAgencyAccount.new(benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id,
                                                                                                writing_agent_id: writing_agent.id,
                                                                                                start_on: Time.now,
                                                                                                is_active: true)
        family.reload
      end

      it 'should not create assister agency' do
        expect(family.assister_agency_accounts.unscoped.length).to eq(1)
        hire_params = { family_id: family.id,
                        terminate_date: TimeKeeper.date_of_record,
                        assister_role_id: writing_agent.id,
                        start_date: DateTime.now.utc.to_datetime,
                        current_assister_account_id: family&.current_assister_agency&.id }

        result = subject.call(hire_params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq true
        family.reload
        expect(family.assister_agency_accounts.unscoped.length).to eq(1)
      end
    end

    context 'hiring new assister' do
      before(:each) do
        family.assister_agency_accounts << BenefitSponsors::Accounts::AssisterAgencyAccount.new(benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id,
                                                                                                writing_agent_id: writing_agent.id,
                                                                                                start_on: Time.now,
                                                                                                is_active: true)
        family.reload
      end

      it 'should terminate old assister and create assister agency account for new assister' do
        expect(family.assister_agency_accounts.unscoped.length).to eq(1)
        hire_params = { family_id: family.id,
                        terminate_date: TimeKeeper.date_of_record,
                        assister_role_id: writing_agent2.id,
                        start_date: DateTime.now,
                        current_assister_account_id: family&.current_assister_agency&.id }

        result = subject.call(hire_params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq true
        family.reload
        expect(family.assister_agency_accounts.unscoped.length).to eq(2)
      end
    end

    context 'hiring assister in imported state' do
      it 'should return failure' do
        writing_agent.update_attributes(aasm_state: 'imported')
        hire_params = { family_id: family.id,
                        terminate_date: TimeKeeper.date_of_record,
                        assister_role_id: writing_agent.id,
                        start_date: DateTime.now,
                        current_assister_account_id: family&.current_assister_agency&.id }

        result = subject.call(hire_params)
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure.messages.map(&:text)).to eq ["Cant Hire Assister with imported state"]
      end
    end

    context 'when invalid params passed' do
      it 'should return failure' do
        hire_params = { family_id: family.id,
                        terminate_date: TimeKeeper.date_of_record,
                        assister_role_id: BSON::ObjectId.new,
                        start_date: DateTime.now,
                        current_assister_account_id: BSON::ObjectId.new }

        result = subject.call(hire_params)
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure.messages.map(&:text)).to eq ["invalid assister_role_id", "missing benefit_sponsors_assister_agency_profile_id in assister role", "invalid assister_account_id"]
      end
    end
  end
end
