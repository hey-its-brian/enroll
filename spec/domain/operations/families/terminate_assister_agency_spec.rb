# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::Families::TerminateAssisterAgency, dbclean: :after_each do

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :male, first_name: 'john', last_name: 'adams', dob: 40.years.ago, ssn: '472743442') }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person)}
  let(:assister_agency_profile) { FactoryBot.build(:benefit_sponsors_organizations_assister_agency_profile)}
  let(:writing_agent)         { FactoryBot.create(:assister_role, benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id) }
  let(:assistor)  do
    assistor = FactoryBot.build(:assister_role, benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id, assister_org_id: "SMECDOA00")
    assistor.save(validate: false)
    assistor
  end

  describe 'assister agency account term params for family' do

    before(:each) do
      family.assister_agency_accounts << BenefitSponsors::Accounts::AssisterAgencyAccount.new(benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id,
                                                                                              writing_agent_id: writing_agent.id,
                                                                                              start_on: Time.now,
                                                                                              is_active: true)
      family.reload
    end

    context 'when valid params passed' do
      it 'should terminate assister agency account' do
        expect(family.current_assister_agency.writing_agent).to eq writing_agent
        terminate_params = { family_id: family.id,
                             terminate_date: TimeKeeper.date_of_record,
                             assister_account_id: family.current_assister_agency&.id }

        result = subject.call(terminate_params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq true
        family.reload
        expect(family.current_assister_agency).to eq nil
      end

      xit 'should terminate assister agency account but should not notify EDI if set to false' do
        expect(family.current_assister_agency.writing_agent).to eq writing_agent
        terminate_params = { family_id: family.id,
                             terminate_date: TimeKeeper.date_of_record,
                             assister_account_id: family.current_assister_agency&.id,
                             notify_edi: false }

        result = subject.call(terminate_params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq "Not notifying EDI"
        family.reload
        expect(family.current_assister_agency).to eq nil
      end

      xit 'should terminate assister agency account but not notify EDI if assister is assistor' do
        family.current_assister_agency.update(is_active: false)
        family.assister_agency_accounts << BenefitSponsors::Accounts::AssisterAgencyAccount.new(benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id,
                                                                                                writing_agent_id: assistor.id,
                                                                                                start_on: Time.now,
                                                                                                is_active: true)
        family.reload
        expect(family.current_assister_agency.writing_agent).to eq assistor
        terminate_params = { family_id: family.id,
                             terminate_date: TimeKeeper.date_of_record,
                             assister_account_id: family.current_assister_agency&.id,
                             notify_edi: true }

        result = subject.call(terminate_params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq "Not notifying EDI because broker is an assistor"
        family.reload
        expect(family.current_assister_agency).to eq nil
      end
    end

    context 'when invalid params passed' do
      it 'should return failure' do
        terminate_params = { family_id: family.id,
                             terminate_date: TimeKeeper.date_of_record,
                             assister_account_id: BSON::ObjectId.new }
        result = subject.call(terminate_params)
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure.messages.map(&:text)).to eq ["invalid assister_account_id"]
      end
    end
  end
end
