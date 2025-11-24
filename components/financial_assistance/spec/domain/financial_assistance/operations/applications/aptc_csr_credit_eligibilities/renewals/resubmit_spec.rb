# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::Resubmit, dbclean: :after_each do
  include Dry::Monads[:result, :do]
  before :all do
    DatabaseCleaner.clean
  end
  let(:hbx_profile)   { FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period) }
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }

  let(:current_year) { TimeKeeper.date_of_record.year }
  let(:renewal_year) { current_year.next }
  let(:person) { FactoryBot.create(:person, :with_consumer_role, first_name: 'test10', last_name: 'test30', gender: 'male') }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:application) do
    FactoryBot.create(
      :financial_assistance_application,
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
      full_medicaid_determination: true
    )
  end
  let(:renewal_draft_application) do
    FactoryBot.create(
      :financial_assistance_application,
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
      aasm_state: 'renewal_draft',
      assistance_year: renewal_year,
      full_medicaid_determination: true
    )
  end
  let(:submitted_application) do
    application = FactoryBot.create(
      :financial_assistance_application,
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
      aasm_state: 'submitted',
      effective_date: Date.new(renewal_year),
      assistance_year: renewal_year,
      full_medicaid_determination: true
    )
    application.workflow_state_transitions.create(from_state: 'renewal_draft', to_state: 'submitted')
    application
  end
  let(:effective_on) { TimeKeeper.date_of_record.beginning_of_year}
  let(:active_enrollment) do
    FactoryBot.create(
      :hbx_enrollment,
      family: family,
      kind: "individual",
      coverage_kind: "health",
      aasm_state: 'coverage_selected',
      effective_on: effective_on,
      hbx_enrollment_members: [FactoryBot.build(:hbx_enrollment_member, applicant_id: family.primary_applicant.id, eligibility_date: effective_on, coverage_start_on: effective_on, is_subscriber: true)]
    )
  end
  let(:applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      :with_home_address,
      person_hbx_id: person.hbx_id,
      is_primary_applicant: true,
      family_member_id: family.primary_applicant.id,
      first_name: 'Test',
      last_name: 'Applicant',
      dob: Date.new(Date.today.year - 22, Date.today.month, Date.today.beginning_of_month.day),
      application: application
    )
  end
  let(:renewal_applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      :with_home_address,
      person_hbx_id: person.hbx_id,
      is_primary_applicant: true,
      family_member_id: family.primary_applicant.id,
      first_name: 'Test',
      last_name: 'Applicant',
      dob: Date.new(Date.today.year - 22, Date.today.month, Date.today.beginning_of_month.day),
      application: renewal_draft_application
    )
  end
  let(:submitted_applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      :with_home_address,
      person_hbx_id: person.hbx_id,
      is_primary_applicant: true,
      family_member_id: family.primary_applicant.id,
      first_name: 'Test',
      last_name: 'Applicant',
      dob: Date.new(Date.today.year - 22, Date.today.month, Date.today.beginning_of_month.day),
      application: submitted_application
    )
  end

  let(:qhp_enabled) { false }

  before do
    benefit_sponsorship
    applicant
    active_enrollment
    allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:skip_eligibility_redetermination).and_return(true)
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(qhp_enabled)
  end

  context 'success' do
    context 'with renewal draft application' do
      before do
        renewal_applicant
        @result = subject.call({ renewal_year: renewal_year })
      end

      it 'returns array of resubmission details' do
        expect(@result.success).to be_truthy
        results = @result.success
        application_hbx_ids = results.collect{|a| a[:application_hbx_id]}
        expect(application_hbx_ids).to include(renewal_draft_application.hbx_id)
        expect(@result.success.first[:original_state]).to eq('renewal_draft')
        expect(@result.success.first[:resubmission_result]).to eq('success')
        expect(@result.success.first[:result_message]).to include('Successfully Published for event determination_requested')
      end
    end

    context 'with submitted renewal application' do
      before do
        renewal_applicant
        submitted_applicant
        @result = subject.call({ renewal_year: renewal_year })
      end

      it 'returns array of resubmission details' do
        expect(@result.success).to be_truthy
        results = @result.success
        application_hbx_ids = results.collect{|a| a[:application_hbx_id]}
        expect(application_hbx_ids).to include(renewal_draft_application.hbx_id)
        expect(application_hbx_ids).to include(submitted_application.hbx_id)
        expect(results.last[:original_state]).to eq('submitted')
        expect(results.last[:resubmission_result]).to eq('success')
        expect(results.last[:result_message]).to include('Successfully Published for event determination_requested')
      end

      it 'sets the assistance_year on the resubmitted application' do
        expect(submitted_application.assistance_year).to eq(renewal_year)
      end

      it 'sets the effective_date on the resubmitted application' do
        expect(submitted_application.effective_date).to eq(Date.new(renewal_year))
      end
    end

    context 'with:
      - qhp_application feature enabled
      - applicant with income evidence in extended ROP state
      ' do
      let(:qhp_enabled) { true }

      before do
        [application, submitted_applicant.application].each do |app|
          app.build_ivl_eligibility_with_evidences
          app.build_aptc_eligibilities_evidences
          app.applicants.each do |applicant|
            income = applicant.aptc_csr_eligibility.income_evidence
            income.current_state = :outstanding
            income.due_on = Date.today + 10.days
            income.due_date_extended_at = Date.today
          end
          app.save!
        end

        submitted_application.predecessor_id = application.id
        submitted_application.save!
      end

      it 'successfully publishes an event for determination request' do
        result = subject.call({ renewal_year: renewal_year })
        expect(result.success?).to be_truthy
        expect(
          result.success.detect { |detail| detail[:application_hbx_id] == submitted_application.hbx_id }[:resubmission_result]
        ).to eq('success')
      end
    end
  end

  context 'failure' do
    context 'with no renewal eligible applications found' do
      let(:target_year) { renewal_year - 5 }

      before do
        renewal_applicant
        @result = subject.call({ renewal_year: target_year })
      end

      it 'returns a failure result' do
        expect(@result.failure?).to be_truthy
        expect(@result.failure).to eq("No renewal eligible applications found for renewal year: #{target_year}")
      end
    end
  end
end
