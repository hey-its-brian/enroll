# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Operations::Application::UpdateOrCreateRelationships, dbclean: :after_each do
  let(:family_id) {BSON::ObjectId.new}
  let!(:application) {FactoryBot.create(:financial_assistance_application, family_id: family_id, aasm_state: 'draft')}
  let!(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      :with_work_phone,
                      :with_work_email,
                      :with_home_address,
                      application: application,
                      ssn: '889984400',
                      dob: (Date.today - 10.years),
                      first_name: 'james',
                      last_name: 'bond',
                      :gender => "male",
                      :is_applying_coverage => true,
                      :citizen_status => "us_citizen",
                      :is_consumer_role => true,
                      :same_with_primary => false,
                      :indian_tribe_member => false,
                      :is_incarcerated => true,
                      :is_primary_applicant => true,
                      :is_consent_applicant => false,
                      :is_disabled => false,
                      :family_member_id => BSON::ObjectId('5f60c648bb40ee0c3d288a83'))
  end

  let!(:applicant2) do
    FactoryBot.create(:financial_assistance_applicant,
                      :with_work_phone,
                      :with_work_email,
                      :with_home_address,
                      application: application,
                      :gender => "male",
                      ssn: '889984401',
                      dob: (Date.today - 10.years),
                      first_name: 'dep1',
                      last_name: 'bond',
                      :is_applying_coverage => true,
                      :citizen_status => "us_citizen",
                      :is_consumer_role => true,
                      :same_with_primary => false,
                      :indian_tribe_member => false,
                      :is_incarcerated => true,
                      :is_primary_applicant => false,
                      :is_consent_applicant => false,
                      :is_disabled => false,
                      :family_member_id => BSON::ObjectId('5f60c648bb40ee0c3d288a84'))
  end

  context 'success' do

    before do
      FinancialAssistance::Relationship.skip_callback(:save, :after, :propagate_applicant)
      application.ensure_relationship_with_primary(applicant2, "spouse")
      FinancialAssistance::Relationship.set_callback(:save, :after, :propagate_applicant)
      relationship_params = {application: application, applicant_id: applicant.id, relative_id: applicant2.id, relationship_kind: 'unrelated'}
      @result = FinancialAssistance::Operations::Application::UpdateOrCreateRelationships.new.call(relationship_params)
    end

    context 'When all the params are valid' do
      it 'should return a success object' do
        expect(@result).to be_a(Dry::Monads::Result::Success)
      end

      it 'should return application' do
        application = @result.value!
        expect(application).to be_a FinancialAssistance::Application
        application.reload
        expect(application.relationships.count).to eq 2
        expect(application.relationships[1].kind).to eq 'unrelated'
        expect(application.relationships[0].kind).to eq 'unrelated'
      end
    end

    context 'When there are three members' do
      let!(:applicant3) do
        FactoryBot.create(:financial_assistance_applicant,
                          :with_work_phone,
                          :with_work_email,
                          :with_home_address,
                          application: application,
                          :gender => "male",
                          ssn: '889984401',
                          dob: (Date.today - 10.years),
                          first_name: 'dep2',
                          last_name: 'bond',
                          :is_applying_coverage => true,
                          :citizen_status => "us_citizen",
                          :is_consumer_role => true,
                          :same_with_primary => false,
                          :indian_tribe_member => false,
                          :is_incarcerated => true,
                          :is_primary_applicant => false,
                          :is_consent_applicant => false,
                          :is_disabled => false,
                          :family_member_id => BSON::ObjectId('5f60c648bb40ee0c3d288a84'))
      end

      before do
        FinancialAssistance::Relationship.skip_callback(:save, :after, :propagate_applicant)
        application.add_or_update_relationships(applicant, applicant2, "spouse")
        application.add_or_update_relationships(applicant, applicant3, "parent")
        application.add_or_update_relationships(applicant2, applicant3, "parent")
        FinancialAssistance::Relationship.set_callback(:save, :after, :propagate_applicant)
      end

      it 'should return existing relationships' do
        expect(application.relationships.count).to eq 6
        expect(application.relationships.map(&:kind)).to match_array(["spouse", "spouse", "child", "parent", "parent", "child"])
      end

      it 'should return application' do
        relationship_params = {application: application, applicant_id: applicant.id, relative_id: applicant2.id, relationship_kind: 'unrelated'}
        @result = FinancialAssistance::Operations::Application::UpdateOrCreateRelationships.new.call(relationship_params)
        application = @result.value!
        application.reload
        expect(application).to be_a FinancialAssistance::Application
        expect(application.relationships.count).to eq 2
        expect(application.relationships[1].kind).to eq 'unrelated'
        expect(application.relationships[0].kind).to eq 'unrelated'
      end
    end
  end

  context 'failure' do
    context 'When application is not present' do
      before do
        relationship_params = {application: nil, applicant_id: applicant.id, relative_id: applicant2.id, relationship_kind: 'unrelated'}
        @result = FinancialAssistance::Operations::Application::UpdateOrCreateRelationships.new.call(relationship_params)
      end
      it 'should return failure' do
        expect(@result).to be_a(Dry::Monads::Result::Failure)
      end

      it 'should return a failed message' do
        expect(@result.failure).to eq :invalid_params
      end
    end

    context 'When applicant_id is not present' do
      before do
        relationship_params = {application: application, applicant_id: nil, relative_id: applicant2.id, relationship_kind: 'unrelated'}
        @result = FinancialAssistance::Operations::Application::UpdateOrCreateRelationships.new.call(relationship_params)
      end
      it 'should return failure' do
        expect(@result).to be_a(Dry::Monads::Result::Failure)
      end

      it 'should return a failed message' do
        expect(@result.failure).to eq :invalid_params
      end
    end

    context 'When relative_id is not present' do
      before do
        relationship_params = {application: application, applicant_id: applicant.id, relative_id: nil, relationship_kind: 'unrelated'}
        @result = FinancialAssistance::Operations::Application::UpdateOrCreateRelationships.new.call(relationship_params)
      end
      it 'should return failure' do
        expect(@result).to be_a(Dry::Monads::Result::Failure)
      end

      it 'should return a failed message' do
        expect(@result.failure).to eq :invalid_params
      end

    end

    context 'When relationship_kind is not present' do
      before do
        relationship_params = {application: application, applicant_id: applicant.id, relative_id: applicant2.id, relationship_kind: nil}
        @result = FinancialAssistance::Operations::Application::UpdateOrCreateRelationships.new.call(relationship_params)
      end
      it 'should return failure' do
        expect(@result).to be_a(Dry::Monads::Result::Failure)
      end

      it 'should return a failed message' do
        expect(@result.failure).to eq :invalid_params
      end
    end

    context 'When applicant_id is same as relative_id' do
      before do
        relationship_params = {application: application, applicant_id: applicant.id, relative_id: applicant.id, relationship_kind: 'unrelated'}
        @result = FinancialAssistance::Operations::Application::UpdateOrCreateRelationships.new.call(relationship_params)
      end
      it 'should return failure' do
        expect(@result).to be_a(Dry::Monads::Result::Failure)
      end

      it 'should return a failed message' do
        expect(@result.failure).to eq :same_predecessor_and_successor
      end
    end

    context 'When applicant is not found' do
      before do
        @relationship_params = {application: application, applicant_id: BSON::ObjectId.new, relative_id: applicant2.id, relationship_kind: 'unrelated'}
        @result = FinancialAssistance::Operations::Application::UpdateOrCreateRelationships.new.call(@relationship_params)
      end
      it 'should return failure' do
        expect(@result).to be_a(Dry::Monads::Result::Failure)
      end

      it 'should return a failed message' do
        expect(@result.failure).to eq "Unable to find Applicant with ID #{@relationship_params[:applicant_id]}."
      end
    end

    context 'When relative is not found' do
      before do
        @relationship_params = {application: application, applicant_id: applicant.id, relative_id: BSON::ObjectId.new, relationship_kind: 'unrelated'}
        @result = FinancialAssistance::Operations::Application::UpdateOrCreateRelationships.new.call(@relationship_params)
      end
      it 'should return failure' do
        expect(@result).to be_a(Dry::Monads::Result::Failure)
      end

      it 'should return a failed message' do
        expect(@result.failure).to eq "Unable to find Applicant with ID #{@relationship_params[:relative_id]}."
      end
    end
  end
end