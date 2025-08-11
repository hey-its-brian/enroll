# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::SubmitDeterminationRequest, dbclean: :after_each do

  describe '#call' do
    let(:person) { FactoryBot.create(:person, :with_ssn, :with_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:current_application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, years_to_renew: 5) }
    let(:current_applicant) do
      FactoryBot.create(
        :financial_assistance_applicant,
        :us_citizen,
        application: current_application,
        person_hbx_id: person.hbx_id,
        family_member_id: family.primary_applicant.id,
        first_name: person.first_name,
        last_name: person.last_name,
        dob: person.dob,
        ssn: person.ssn,
        no_ssn: '0'
      )
    end

    let(:hbx_profile)   { FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period) }
    let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }

    let(:renewal_application) do
      ::FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::Renew.new.call(
        { family_id: family.id, renewal_year: TimeKeeper.date_of_record.year.next }
      ).success
    end

    before :each do
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:skip_eligibility_redetermination).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      benefit_sponsorship
      current_applicant.build_aptc_eligibilities_evidences
      current_applicant.build_ivl_eligibility_with_evidences
      current_applicant.eligibilities.flat_map(&:evidences).each_with_index do |evidence, index|
        index.even? ? evidence.mark_as_outstanding : evidence.mark_as_verified
      end
      current_applicant.save!
      family.latest_application_gid = current_application.to_global_id.uri.to_s
      family.save!
      renewal_application
    end

    context 'when:
      - the family has an existing application
      - the application is in renewal_draft state
      ' do

      let(:result) { subject.call(application_id: renewal_application.id) }

      it 'successfully submits the determination request' do
        expect(result).to be_success
      end

      it 'retains the ROP information' do
        result
        renewal_application.reload.applicants.flat_map(&:eligibilities).flat_map(&:evidences).each do |evidence|
          # Either the evidence is in verified state or in outstanding state with a due_on
          expect(evidence.verified? || (evidence.outstanding? && evidence.due_on.present?)).to be_truthy
        end
      end

      it 'creates history entries for the evidence during ROP retention' do
        result
        renewal_application.reload.applicants.each do |applicant|
          applicant.eligibilities.flat_map(&:evidences).each do |evidence|
            expect(evidence.verification_histories).not_to be_empty
          end
        end
      end
    end
  end
end
