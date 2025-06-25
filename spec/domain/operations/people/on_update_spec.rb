# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::People::OnUpdate, dbclean: :after_each do
  context 'with invalid params' do
    context 'missing gid' do
      let(:params) { {} }

      it 'returns failure' do
        result = described_class.new.call(params)
        expect(result.failure?).to be true
        expect(result.failure).to eq('Invalid parameters, missing gid for {}')
      end
    end

    context 'missing payload' do
      let(:params) { { gid: 'some-gid' } }

      it 'returns failure' do
        result = described_class.new.call(params)
        expect(result.failure?).to be true
        expect(result.failure).to eq('Invalid parameters, missing payload for {:gid=>"some-gid"}')
      end
    end

    context 'invalid payload type' do
      let(:params) { { gid: 'some-gid', payload: 'not-a-hash' } }

      it 'returns failure' do
        result = described_class.new.call(params)
        expect(result.failure?).to be true
        expect(result.failure).to eq('Invalid parameters, missing payload for {:gid=>"some-gid", :payload=>"not-a-hash"}')
      end
    end
  end

  context 'with valid params' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:gid) { person.to_global_id.uri }
    let(:changes) { {} }
    let(:params) { { gid: gid, payload: changes } }

    before do
      tribe_setting_double = double('tribe_setting')
      allow(tribe_setting_double).to receive(:item).and_return([:tribal_id, :tribal_name])

      identifying_setting_double = double('identifying_setting')
      allow(identifying_setting_double).to receive(:item).and_return([:first_name, :dob])

      allow(EnrollRegistry[:consumer_role_hub_call]).to receive(:setting).with(:indian_tribe_attributes).and_return(tribe_setting_double)
      allow(EnrollRegistry[:consumer_role_hub_call]).to receive(:setting).with(:identifying_information_attributes).and_return(identifying_setting_double)
    end

    context 'when consumer role exists' do
      shared_examples 'calls DetermineVerifications and returns success' do
        before { allow(::Operations::Individual::DetermineVerifications).to receive(:new).and_return(double(call: Dry::Monads::Result::Success.new('result'))) }

        it 'calls DetermineVerifications and returns success' do
          result = described_class.new.call(params)
          expect(result.success?).to be true
        end
      end

      shared_examples 'returns success without calling DetermineVerifications' do
        it 'returns success with nil value and does not call DetermineVerifications' do
          result = described_class.new.call(params)
          expect(result.success?).to be true
          expect(result.success).to be_nil
        end
      end

      context 'without changes' do
        include_examples 'returns success without calling DetermineVerifications'
      end

      context 'with changes' do
        context 'for no_ssn' do
          let(:changes) { { no_ssn: no_ssn_change } }

          context 'to attested' do
            let(:no_ssn_change) { ['0', '1'] }
            include_examples 'calls DetermineVerifications and returns success'
          end

          context 'to unattested' do
            let(:no_ssn_change) { ['1', '0'] }
            include_examples 'returns success without calling DetermineVerifications'
          end
        end

        context 'for tribe status attributes' do
          context 'when tribe status changes from empty to present' do
            let(:changes) { { tribal_id: ['', 'some-id'] } }
            include_examples 'calls DetermineVerifications and returns success'
          end

          context 'when tribe status changes from present to empty' do
            let(:changes) { { tribal_id: ['some-id', ''] } }
            include_examples 'calls DetermineVerifications and returns success'
          end

          context 'when tribe status changes from nil to empty' do
            let(:changes) { { tribal_id: [nil, ''] } }
            include_examples 'returns success without calling DetermineVerifications'
          end
        end

        context 'for identifying information attributes' do
          context 'when identifying information changes' do
            let(:changes) { { dob: ['1/1/2000', '1/1/2004'] } }
            include_examples 'calls DetermineVerifications and returns success'
          end

          context 'when non-identifying information changes' do
            let(:changes) { { middle_name: ['old-name', 'new-name'] } }
            include_examples 'calls DetermineVerifications and returns success'
          end
        end
      end
    end

    context 'when consumer role does not exist' do
      before { allow_any_instance_of(Person).to receive(:consumer_role).and_return(nil) }

      it 'returns failure' do
        result = described_class.new.call(params)
        expect(result.failure?).to be true
        expect(result.failure).to eq("ConsumerRole not found for gid: #{gid}")
      end
    end
  end
end
