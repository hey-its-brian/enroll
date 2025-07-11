# frozen_string_literal: true

require 'rails_helper'


RSpec.describe Operations::Sbm::Applications::CancelPreviousApplications, type: :model do
  after :all do
    DatabaseCleaner.clean
  end

  let(:family) { FactoryBot.create(:family, :with_primary_family_member) }
  let(:family2) { FactoryBot.create(:family, :with_primary_family_member) }
  let(:ivl_app1) do
    FactoryBot.create(:individual_market_application, :initial, family_id: family.id)
  end

  let(:fa_app1) do
    FactoryBot.create(:application, aasm_state: 'draft', family_id: family.id, assistance_year: nil)
  end

  let(:ivl_app2) do
    FactoryBot.create(:individual_market_application, :determined, family_id: family.id)
  end

  let(:fa_app2) do
    FactoryBot.create(:application, aasm_state: 'determined', family_id: family.id)
  end

  let(:ivl_app3) do
    FactoryBot.create(:individual_market_application, :initial, family_id: family.id)
  end

  let(:fa_app3) do
    FactoryBot.create(:application, aasm_state: 'draft', family_id: family.id, assistance_year: Date.today.year)
  end

  let(:ivl_app4) do
    FactoryBot.create(:individual_market_application, :initial, family_id: family.id, assistance_year: Date.today.year + 1)
  end

  let(:fa_app4) do
    FactoryBot.create(:application, aasm_state: 'draft', family_id: family.id, assistance_year: Date.today.year + 1)
  end

  let(:ivl_app5) do
    FactoryBot.create(:individual_market_application, :initial, family_id: family2.id)
  end

  let(:fa_app5) do
    FactoryBot.create(:application, aasm_state: 'draft', family_id: family2.id)
  end

  let(:ivl_input_application) do
    FactoryBot.create(:individual_market_application, :initial, family_id: family.id)
  end

  let(:fa_input_application) do
    FactoryBot.create(:application, aasm_state: 'draft', family_id: family.id, assistance_year: Date.today.year)
  end

  describe '#call' do
    context 'with valid individual market application' do
      let(:params) { { application: ivl_input_application } }

      before do
        ivl_app1
        ivl_app2
        ivl_app3
        ivl_app4
        ivl_app5
        fa_input_application
        @result = subject.call(params)
      end

      it 'returns a success' do
        expect(@result).to be_success
        expect(@result.success).to match(/Cancelled draft applications with hbx_ids:/)
      end

      it 'cancels all previous draft applications for the family' do
        expect(ivl_app1.reload.current_state).to eq(:cancelled)
        expect(ivl_app3.reload.current_state).to eq(:cancelled)
      end

      it 'adds a comment and reason to the cancelled applications state history' do
        expect(ivl_app1.reload.state_histories.last.comment).to eq("Cancelled by the system due to new application: #{ivl_input_application.hbx_id} creation")
        expect(ivl_app1.reload.state_histories.last.reason).to eq("Cancelled by the system due to new application: #{ivl_input_application.hbx_id} creation")
      end

      it 'does not cancel applications for other assistance years' do
        expect(ivl_app4.reload.current_state).to eq(:initial)
      end

      it 'does not cancel the input application' do
        expect(ivl_input_application.reload.current_state).to eq(:initial)
      end

      it 'does not cancel non-draft applications' do
        expect(ivl_app2.reload.current_state).to eq(:determined)
      end

      it 'does not cancel applications for other families' do
        expect(ivl_app5.reload.current_state).to eq(:initial)
      end

      it 'does cancel FA applications' do
        expect(fa_input_application.reload.aasm_state).to eq("cancelled")
      end
    end

    context 'with valid financial assistance application' do
      let(:params) { { application: fa_input_application } }

      before do
        fa_app1
        fa_app2
        fa_app3
        fa_app4
        fa_app5
        ivl_input_application
        @result = subject.call(params)
      end

      it 'returns a success' do
        expect(@result).to be_success
        expect(@result.success).to match(/Cancelled draft applications with hbx_ids:/)
      end

      it 'cancels previous draft applications for the family with assistance year nil' do
        expect(fa_app1.reload.aasm_state).to eq("cancelled")
      end

      it 'cancels previous draft applications for the family with same assistance year' do
        expect(fa_app3.reload.aasm_state).to eq("cancelled")
      end

      it 'adds a comment and reason to the cancelled applications state history' do
        expect(fa_app1.reload.workflow_state_transitions.last.comment).to eq("Cancelled by the system due to new application: #{fa_input_application.hbx_id} creation")
        expect(fa_app1.reload.workflow_state_transitions.last.reason).to eq("Cancelled by the system due to new application: #{fa_input_application.hbx_id} creation")
      end

      it 'does not cancel applications for other assistance years' do
        expect(fa_app4.reload.aasm_state).to eq("draft")
      end

      it 'does not cancel the input application' do
        expect(fa_input_application.reload.aasm_state).to eq("draft")
      end

      it 'does not cancel non-draft applications' do
        expect(fa_app2.reload.aasm_state).to eq("determined")
      end

      it 'does not cancel applications for other families' do
        expect(fa_app5.reload.aasm_state).to eq("draft")
      end

      it 'does cancel IVL applications' do
        expect(ivl_input_application.reload.current_state).to eq(:cancelled)
      end
    end

    context 'with invalid parameters' do
      context 'without input application' do
        let(:params) { { application: nil } }

        it 'returns a failure' do
          expect(subject.call(params).failure).to eq('Invalid parameters: application is required.')
        end
      end

      context 'without family_id' do
        let(:input_application) { FactoryBot.create(:financial_assistance_application, :draft, assistance_year: Date.today.year) }
        let(:params) { { application: input_application } }

        it 'returns a failure' do
          expect(subject.call(params).failure).to eq('Missing family_id for application to fetch previous applications')
        end
      end

      context 'without assistance_year' do
        let(:input_application) { FactoryBot.create(:financial_assistance_application, :draft, family_id: family.id, assistance_year: nil) }
        let(:params) { { application: input_application } }

        it 'returns a failure' do
          expect(subject.call(params).failure).to eq('Missing assistance_year for application to fetch previous applications')
        end
      end
    end
  end

end
