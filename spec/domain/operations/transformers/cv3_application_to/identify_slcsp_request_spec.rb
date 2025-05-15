# frozen_string_literal: true

require "#{FinancialAssistance::Engine.root}/spec/shared_examples/medicaid_gateway/test_case_d_response"

RSpec.describe ::Operations::Transformers::Cv3ApplicationTo::IdentifySlcspRequest, type: :model, dbclean: :after_each do
  let(:enabled) { false }

  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(enabled)
  end

  describe '#call' do
    subject { described_class.new.call({ fa_application: fa_application, mm_application: mm_application }) }

    context 'invalid fa_application, mm_application input' do
      let(:fa_application) { { test: 'test' } }
      let(:mm_application) { { test: 'test' } }

      it 'should return a failure' do
        expect(subject.failure?).to be_truthy
      end
    end

    context 'valid input' do
      include_context 'cms ME simple_scenarios test_case_d'

      let(:member_dob) { Date.new(current_date.year - 12, current_date.month, current_date.day) }
      let(:person) { FactoryBot.create(:person, :with_consumer_role, first_name: 'Gerald', last_name: 'Rivers', dob: member_dob) }
      let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
      let(:application) { FactoryBot.create(:financial_assistance_application, hbx_id: '200000126', aasm_state: "submitted", family_id: family.id, effective_date: TimeKeeper.date_of_record) }
      let(:applicant) { FactoryBot.create(:financial_assistance_applicant, application: application, is_primary_applicant: true) }
      let(:mm_application) { ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(response_payload).success }
      let(:fa_application) { application }

      before do
        person.update_attributes!(hbx_id: '95')
        applicant.update_attributes!(person_hbx_id: person.hbx_id)
      end

      context 'when qhp_application feature is disabled' do
        it 'returns expected result including family_id & family_member_id' do
          expect(subject.success?).to be_truthy
          expect(subject.success[0]).to eq(family)
          expect(subject.success[1][:family_id]).to be_present
          expect(
            subject.success[1].dig(:households, 0, :members, 0, :family_member_id)
          ).to be_present
          expect(subject.success[1][:data_source]).to eq('family')
        end
      end

      context 'when qhp_application feature is enabled' do
        let(:enabled) { true }

        it 'returns expected result including application_id & applicant_id' do
          expect(subject.success?).to be_truthy
          expect(subject.success[0]).to eq('Family object is not needed')
          expect(subject.success[1][:application_id]).to be_present
          expect(
            subject.success[1].dig(:households, 0, :members, 0, :applicant_id)
          ).to be_present
          expect(subject.success[1][:data_source]).to eq('fa_application')
        end
      end
    end
  end
end
