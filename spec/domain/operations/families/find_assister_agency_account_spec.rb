# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::Families::FindAssisterAgencyAccount, dbclean: :after_each do

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :male, first_name: 'john', last_name: 'adams', dob: 40.years.ago, ssn: '472743442') }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person)}
  let(:assister_agency_profile) { FactoryBot.build(:benefit_sponsors_organizations_assister_agency_profile)}
  let(:writing_agent)         { FactoryBot.create(:assister_role, benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id) }

  describe 'assister agency account find' do

    before(:each) do
      family.assister_agency_accounts << BenefitSponsors::Accounts::AssisterAgencyAccount.new(benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id,
                                                                                              writing_agent_id: writing_agent.id,
                                                                                              start_on: Time.now,
                                                                                              is_active: true)
      family.reload
    end

    context 'when assister_account_id passed' do
      it 'should return family assister agency account' do
        result = subject.call({assister_account_id: family.current_assister_agency.id, family_id: family.id})
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq family.current_assister_agency
      end
    end

    context 'when invalid params passed' do
      it 'should return failure' do
        result = subject.call({assister_account_id: family.current_assister_agency.id})
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to eq "Invalid params for AssisterAgencyAccount"
      end

      it 'should return failure' do
        family_id = BSON::ObjectId.new
        result = subject.call({assister_account_id: family.current_assister_agency.id, family_id: family_id})
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to eq "Unable to find AssisterAgencyAccount with ID #{family.current_assister_agency.id} for Family #{family_id}."
      end
    end
  end
end
