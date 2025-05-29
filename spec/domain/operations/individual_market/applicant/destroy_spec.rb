# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::IndividualMarket::Applicant::Destroy, dbclean: :after_each do

  let!(:application) { FactoryBot.create(:individual_market_application, :initial, :with_applicants) }
  let!(:applicant) do
    application.primary_applicant
  end
  let!(:applicant2) do
    application.non_primary_applicants.first
  end

  before do
    @result = subject.call(input_params)
  end

  context 'for failures' do
    context 'invalid input' do
      let(:input_params) { 'test' }

      it 'should return a failure' do
        expect(@result.failure).to eq("Given input: test is not a valid IndividualMarket::Applicant.")
      end
    end

    context 'applicant is primary' do
      let(:input_params) { applicant }

      it 'should return a failure' do
        expect(@result.failure).to eq("Given applicant with id: #{applicant.id} is a primary applicant, cannot be destroyed/deleted.")
      end
    end

    context 'application is past initial state' do
      let(:input_params) do
        application.update_attributes!(current_state: 'submitted')
        applicant2
      end

      it 'should return a failure' do
        expect(@result.failure).to eq("The application: #{application.id} for given applicant with id: #{applicant2.id} has already been submitted, applicant cannot be destroyed/deleted.")
      end
    end
  end

  context 'success' do
    context 'no relationships' do
      let(:input_params) { applicant2 }

      it 'should return success' do
        expect(@result.success).to eq("Successfully destroyed applicant with id: #{applicant2.id}.")
      end

      it 'should return only one applicant' do
        expect(application.applicants.count).to eq(1)
      end

      it 'should destroy applicant' do
        expect(application.applicants.where(id: applicant2.id).first).to be_nil
      end
    end

    context 'with relationships' do
      let(:input_params) do
        applicant2
      end

      it 'should return success' do
        expect(@result.success).to eq("Successfully destroyed applicant with id: #{applicant2.id}.")
      end

      it 'should return only one applicant' do
        expect(application.applicants.count).to eq(1)
      end

      it 'should destroy applicant' do
        expect(application.applicants.where(id: applicant2.id).first).to be_nil
      end

      it 'should destroy relationships' do
        expect(application.relationships.count).to be_zero
      end
    end
  end
end
