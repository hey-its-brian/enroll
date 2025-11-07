# frozen_string_literal: true

require 'rails_helper'
require "#{FinancialAssistance::Engine.root}/spec/shared_examples/rrv/medicare/test_rrv_medicare_response"

RSpec.describe ::FinancialAssistance::Operations::Applications::Rrv::GenerateResponseReport, dbclean: :after_each do
  include_context 'FDSH RRV Medicare sample response'

  let!(:family) { FactoryBot.create(:family, :with_primary_family_member)}
  let!(:application) do
    FactoryBot.create(:financial_assistance_application, hbx_id: '200000126', aasm_state: "determined", family_id: family.id)
  end

  let!(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      eligibility_determination_id: nil,
                      person_hbx_id: '1629165429385938',
                      is_primary_applicant: true,
                      first_name: 'esi',
                      last_name: 'evidence',
                      ssn: "518124854",
                      dob: Date.new(1988, 11, 11),
                      is_ia_eligible: true,
                      family_member_id: family.primary_family_member.id,
                      application: application)
  end

  let!(:eligibility_determination) { FactoryBot.create(:financial_assistance_eligibility_determination, application: application, csr_percent_as_integer: 73) }
  let(:hbx_profile) {FactoryBot.create(:hbx_profile)}
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
  let(:benefit_coverage_period) { hbx_profile.benefit_sponsorship.benefit_coverage_periods.first }

  let(:obj)  { FinancialAssistance::Operations::Applications::Rrv::CreateRrvRequest.new }

  let(:update_benchmark_premiums) do
    applicant.benchmark_premiums = {
      health_only_lcsp_premiums: [{ member_identifier: applicant.person_hbx_id, monthly_premium: 90.0 }],
      health_only_slcsp_premiums: [{ member_identifier: applicant.person_hbx_id, monthly_premium: 90.0 }]
    }

    applicant.save!
  end
  let!(:enrollment) { FactoryBot.create(:hbx_enrollment, :with_enrollment_members, :with_health_product, family: family, enrollment_members: family.family_members) }

  before do
    allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:non_esi_mec_determination).and_return(true)
    allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:ifsv_determination).and_return(true)
    allow(HbxProfile).to receive(:current_hbx).and_return hbx_profile
    allow(hbx_profile).to receive(:benefit_sponsorship).and_return benefit_sponsorship
    allow(benefit_sponsorship).to receive(:current_benefit_period).and_return(benefit_coverage_period)
    update_benchmark_premiums
    @applicant = application.applicants.first
    @applicant.build_aptc_eligibilities_evidences
    @applicant.save!
    ::FinancialAssistance::Operations::Applications::Rrv::NonEsiEvidence::DetermineAndStoreResponse.new.call({payload: response_payload, applicant_identifier: @applicant.person_hbx_id, call_type: 'hub_call'})
  end


  it 'should generate RRV response report successfully' do
    @applicant.reload
    result = subject.call({assistance_year: application.assistance_year, from_date: Date.today - 1.day})
    expect(result).to be_success
    expect(result.success).to include("RRV report generated successfully at [\"rrv_results_summary_0.csv\"]")
  end
end
