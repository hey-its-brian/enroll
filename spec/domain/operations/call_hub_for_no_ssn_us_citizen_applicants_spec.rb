# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe Operations::CallHubForNoSsnUsCitizenApplicants, type: :model, dbclean: :after_each do
  let(:operation) { described_class.new }
  let(:params) { {} }

  describe '#call' do
    context 'when there are no eligible families' do
      before do
        allow(::FinancialAssistance::Application.collection).to receive(:aggregate).and_return([])
      end

      it 'returns success with empty families' do
        result = subject.call
        expect(result).to be_success
        csv_file_name = result.success.split(': ').last
        csv_data = CSV.parse(File.read(csv_file_name))
        expect(csv_data[1]).to be_nil
      end
    end

    context 'when there are eligible families' do
      let!(:person) { FactoryBot.create(:person, :with_consumer_role) }
      let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
      let!(:application) do
        FactoryBot.create(:financial_assistance_application,
                          family_id: family.id,
                          aasm_state: 'determined')
      end
      let!(:applicant) do
        FactoryBot.create(:financial_assistance_applicant,
                          application: application,
                          encrypted_ssn: nil,
                          citizen_status: 'us_citizen',
                          person_hbx_id: person.hbx_id,
                          first_name: 'John',
                          last_name: 'Doe')
      end
      let!(:individual_market_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }

      before do
        allow(::FinancialAssistance::Application.collection).to receive(:aggregate).and_return([
          { '_id' => family.id, 'latest_submitted_at' => Time.current }
        ])
        allow(Family).to receive(:where).with(:id.in => [family.id]).and_return([family])
        allow(family).to receive(:latest_application).and_return(application)
        allow(applicant).to receive(:individual_market_eligibility).and_return(individual_market_eligibility)
      end

      context 'when applicant has eligible evidences' do
        let(:ssn_evidence) do
          double('Evidence',
                 key: 'social_security_number_evidence',
                 current_state: :pending,
                 verification_histories: [double('History', action: 'SSA VLP Hub Request')],
                 request_results: [])
        end
        let(:citizenship_evidence) do
          double('Evidence',
                 key: 'citizenship_evidence',
                 current_state: :pending,
                 verification_histories: [double('History', action: 'SSA VLP Hub Request')],
                 request_results: [])
        end
        let(:hub_verification_service) { double('SsaVlpVerification') }

        before do
          allow(individual_market_eligibility).to receive(:evidences).and_return([ssn_evidence, citizenship_evidence])
          allow(Operations::Eligibilities::V3::IndividualMarket::SsaVlpVerification).to receive(:new).and_return(hub_verification_service)
          allow(hub_verification_service).to receive(:call).and_return(double('result'))
          @result = operation.call
        end

        it 'generates CSV with hub call made' do
          csv_file_name = @result.success.split(': ').last
          csv_data = CSV.parse(File.read(csv_file_name))

          expect(csv_data[0]).to eq(["Primary Person Hbx Id", "Application ID", "Application Assistance Year", "Application Submitted At", "Applicant HBX ID", "SSN Evidence Status", "Citizenship Evidence Status", "Hub Call Made"])

          row1 = csv_data[1]
          expect(row1[0]).to eq(person.hbx_id)
          expect(row1[1]).to eq(application.hbx_id)
          expect(row1[2]).to eq(application.assistance_year.to_s)
          expect(row1[3]).to eq(application.submitted_at.to_s)
          expect(row1[4]).to eq(applicant.person_hbx_id)
          expect(row1[5]).to eq("pending")
          expect(row1[6]).to eq("pending")
          expect(row1[7]).to eq("true")
        end
      end

      context 'when evidences have request results' do
        let(:evidence_with_results) do
          double('Evidence',
                 key: 'social_security_number_evidence',
                 verification_histories: [double('History', action: 'SSA VLP Hub Request')],
                 request_results: [double('Result')])
        end

        before do
          allow(individual_market_eligibility).to receive(:evidences).and_return([evidence_with_results])
          @result = subject.call
        end

        it 'does not make hub call when evidence has request results' do
          csv_file_name = @result.success.split(': ').last
          csv_data = CSV.parse(File.read(csv_file_name))
          expect(csv_data[1]).to be_nil
        end
      end
    end
  end
end