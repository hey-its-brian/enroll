# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "RenewalService", dbclean: :after_each do
  include Dry::Monads[:result, :do]

  before :all do
    DatabaseCleaner.clean
  end

  let(:current_year) { TimeKeeper.date_of_record.year }
  let(:renewal_year) { current_year.next }
  let!(:hbx_profile)   { FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period) }
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
  let(:benefit_coverage_period) { hbx_profile.benefit_sponsorship.benefit_coverage_periods.first }
  let(:person) do
    FactoryBot.create(:person, :with_consumer_role, first_name: 'test10', last_name: 'test30', gender: 'male', hbx_id: '100095')
  end
  let(:family) do
    FactoryBot.create(:family, :with_primary_family_member, person: person)
  end
  let!(:application) do
    FactoryBot.create(:financial_assistance_application,
                      family_id: family.id,
                      is_renewal_authorized: false,
                      is_requesting_voter_registration_application_in_mail: true,
                      years_to_renew: 5,
                      medicaid_terms: true,
                      report_change_terms: true,
                      medicaid_insurance_collection_terms: true,
                      parent_living_out_of_home_terms: true,
                      attestation_terms: true,
                      submission_terms: true,
                      aasm_state: 'determined',
                      assistance_year: current_year,
                      full_medicaid_determination: true)
  end

  let(:effective_on) { TimeKeeper.date_of_record.beginning_of_year}
  let!(:active_enrollment) do
    FactoryBot.create(:hbx_enrollment,
                      family: family,
                      kind: "individual",
                      coverage_kind: "health",
                      aasm_state: 'coverage_selected',
                      effective_on: effective_on,
                      hbx_enrollment_members: [
                        FactoryBot.build(:hbx_enrollment_member, applicant_id: family.primary_applicant.id, eligibility_date: effective_on, coverage_start_on: effective_on, is_subscriber: true)
                      ])
  end
  let!(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      person_hbx_id: '100095',
                      is_primary_applicant: true,
                      family_member_id: family.primary_applicant.id,
                      first_name: 'Test',
                      last_name: 'Applicant',
                      dob: Date.new(Date.today.year - 22, Date.today.month, Date.today.beginning_of_month.day),
                      application: application)
  end

  before do
    allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:skip_eligibility_redetermination).and_return(true)
    family.update_attributes(latest_application_gid: application.to_global_id.to_s)
    invoke_renewal_service_script(renewal_year, [person.hbx_id, "14589785", ""])
  end

  it 'should generate matching logger' do
    log_files = Dir.glob("#{Rails.root}/log/renewal_service_*.log")
    expect(log_files).to_not be_empty
  end
end

def invoke_renewal_service_script(renewal_year, hbx_ids)
  original_argv = ARGV.dup
  ARGV.replace([renewal_year.to_s, hbx_ids.join(',')])
  renewal_service_script = File.join(Rails.root, "script/application_renewals/renewal_service.rb")
  load renewal_service_script
ensure
  ARGV.replace(original_argv)
end
