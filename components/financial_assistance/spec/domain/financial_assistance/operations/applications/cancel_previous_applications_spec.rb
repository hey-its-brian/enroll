# frozen_string_literal: true

require 'rails_helper'


RSpec.describe FinancialAssistance::Operations::Applications::CancelPreviousApplications, type: :model do
  after :all do
    DatabaseCleaner.clean
  end

  let(:family_id) { BSON::ObjectId.new }
  let(:app1) do
    FactoryBot.create(:financial_assistance_application, :draft, family_id: family_id)
  end

  let(:app2) do
    FactoryBot.create(:financial_assistance_application, family_id: family_id)
  end

  let(:app3) do
    FactoryBot.create(:financial_assistance_application, :draft, family_id: family_id)
  end

  let(:input_application) do
    FactoryBot.create(:financial_assistance_application, :draft, family_id: family_id)
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:params) { { application: input_application } }

      before do
        app1
        app2
        app3
        @result = subject.call(params)
      end

      it 'returns a success' do
        expect(@result).to be_success
        expect(@result.success).to match(/Cancelled all previous draft applications with hbx_ids:/)
      end

      it 'cancels all previous draft applications for the family' do
        expect(app1.reload).to be_cancelled
        expect(app2.reload).not_to be_cancelled
        expect(app3.reload).to be_cancelled
      end
    end

    context 'with invalid parameters' do
      context 'without input application' do
        let(:params) { { application: nil } }

        it 'returns a failure' do
          expect(subject.call(params).failure).to eq('Invalid parameters: application is required.')
        end
      end

      context 'input application without family_id' do
        let(:input_application) { FactoryBot.create(:financial_assistance_application, :draft) }
        let(:params) { { application: input_application } }

        it 'returns a failure' do
          expect(subject.call(params).failure).to eq(
            'Missing family_id for application to fetch previous applications'
          )
        end
      end
    end
  end

end
