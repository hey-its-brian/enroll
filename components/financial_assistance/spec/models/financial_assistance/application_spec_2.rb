# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::FinancialAssistance::Application, type: :model do

  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:application1) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }

  let(:application2) do
    FactoryBot.create(
      :financial_assistance_application,
      family_id: family.id,
      hbx_id: app_hbx_id
    )
  end

  describe 'hbx_id' do
    before do
      application1
      described_class.remove_indexes
      described_class.create_indexes
    end

    context 'when hbx_id is not unique' do
      let(:app_hbx_id) { application1.hbx_id }

      it 'raises an error' do
        expect { application2 }.to raise_error(
          Mongo::Error::OperationFailure
        ).with_message(
          /E11000 duplicate key error collection/
        )
      end
    end

    context 'when hbx_id is unique' do
      let(:app_hbx_id) { '12345678901234567890' }

      it 'creates a new tax household group' do
        expect(application2).to be_a(described_class)
      end
    end
  end

  describe '#record_transition' do
    let(:application) { FactoryBot.create(:financial_assistance_application, aasm_state: 'draft', family_id: family.id) }
    let(:latest_wfst) { application.workflow_state_transitions.order_by(:created_at.desc).first }

    context 'when additional arguments are passed' do
      let(:reason) { 'Cancelled by the system due to new application creation' }

      context 'when both reason and comment are passed' do
        before do
          application.cancel!({ reason: reason, comment: reason })
        end

        it 'creates a new transition record' do
          expect(application.cancelled?).to be_truthy
          expect(latest_wfst.to_state).to eq('cancelled')
          expect(latest_wfst.from_state).to eq('draft')
        end

        it 'sets the additional transition attributes correctly' do
          expect(latest_wfst.reason).to eq(reason)
          expect(latest_wfst.comment).to eq(reason)
        end
      end

      context 'when only reason is passed' do
        before do
          application.cancel!({ reason: reason })
        end

        it 'creates a new transition record' do
          expect(application.cancelled?).to be_truthy
          expect(latest_wfst.to_state).to eq('cancelled')
          expect(latest_wfst.from_state).to eq('draft')
        end

        it 'sets the additional transition attributes correctly' do
          expect(latest_wfst.reason).to eq(reason)
          expect(latest_wfst.comment).to be_nil
        end
      end

      context 'when only comment is passed' do
        before do
          application.cancel!({ comment: reason })
        end

        it 'creates a new transition record' do
          expect(application.cancelled?).to be_truthy
          expect(latest_wfst.to_state).to eq('cancelled')
          expect(latest_wfst.from_state).to eq('draft')
        end

        it 'sets the additional transition attributes correctly' do
          expect(latest_wfst.reason).to be_nil
          expect(latest_wfst.comment).to eq(reason)
        end
      end
    end

    context 'when no additional arguments are passed' do
      before do
        application.cancel!
      end

      it 'creates a new transition record' do
        expect(application.cancelled?).to be_truthy
        expect(latest_wfst.to_state).to eq('cancelled')
        expect(latest_wfst.from_state).to eq('draft')
      end

      it 'sets the additional transition attributes correctly' do
        expect(latest_wfst.reason).to be_nil
        expect(latest_wfst.comment).to be_nil
      end
    end
  end

  describe 'fields' do
    it { is_expected.to have_field(:origin).of_type(Symbol) }
    it { is_expected.to have_field(:generation_reason).of_type(Symbol) }
  end

  describe 'validations' do
    before :each do
      allow(EnrollRegistry).to receive(:feature_enabled?).and_return(enabled)
    end

    describe 'validates origin' do
      let(:app) { FactoryBot.build(:financial_assistance_application, origin: origin, family_id: family.id) }

      context 'when qhp application feature is not enabled' do
        let(:enabled) { false }

        context 'when origin is not present' do
          let(:origin) { nil }

          it 'is valid' do
            expect(app.valid?).to be_truthy
          end
        end
      end

      context 'when qhp application feature is enabled' do
        let(:enabled) { true }

        context 'when origin is not present' do
          let(:origin) { nil }

          it 'is not valid' do
            expect(app.valid?).to be_falsey
            expect(app.errors[:origin]).to include("can't be blank")
          end
        end

        context 'when origin is not valid' do
          let(:origin) { 'invalid_source' }

          it 'is not valid' do
            expect(app.valid?).to be_falsey
            expect(app.errors[:origin]).to include("is not included in the list")
          end
        end

        context 'when origin is valid' do
          let(:origin) { :user }

          it 'is valid' do
            expect(app.valid?).to be_truthy
          end
        end
      end
    end

    describe 'validates generation_reason' do
      let(:app) { FactoryBot.build(:financial_assistance_application, generation_reason: generation_reason, family_id: family.id) }

      context 'when qhp application feature is not enabled' do
        let(:enabled) { false }

        context 'when generation_reason is not present' do
          let(:generation_reason) { nil }

          it 'is valid' do
            expect(app.valid?).to be_truthy
          end
        end
      end

      context 'when qhp application feature is enabled' do
        let(:enabled) { true }

        context 'when generation_reason is not present' do
          let(:generation_reason) { nil }

          it 'is not valid' do
            expect(app.valid?).to be_falsey
            expect(app.errors[:generation_reason]).to include("can't be blank")
          end
        end

        context 'when generation_reason is not valid' do
          let(:generation_reason) { 'invalid_reason' }

          it 'is not valid' do
            expect(app.valid?).to be_falsey
            expect(app.errors[:generation_reason]).to include("is not included in the list")
          end
        end

        context 'when generation_reason is valid' do
          let(:generation_reason) { :manual }

          it 'is valid' do
            expect(app.valid?).to be_truthy
          end
        end
      end
    end
  end
end
