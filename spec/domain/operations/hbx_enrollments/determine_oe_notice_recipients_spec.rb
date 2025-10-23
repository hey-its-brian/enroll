# frozen_string_literal: true

require 'rails_helper'

# corresponds to service object called from `rails runner script/oeg_oeq_notice_triggers.rb oeg_oeq`
RSpec.describe Operations::HbxEnrollments::DetermineOeNoticeRecipients, dbclean: :around_each do
  let(:hbx_profile) { FactoryBot.create(:hbx_profile) }
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
  let(:person1) { FactoryBot.create(:person, :with_consumer_role, :with_ssn) }
  let(:family1) { FactoryBot.create(:family, :with_primary_family_member, person: person1) }

  let(:faa1) do
    FactoryBot.create(
      :financial_assistance_application,
      aasm_state: faa1_state,
      family_id: family1.id,
      assistance_year: TimeKeeper.date_of_record.next_year.year,
      applicants: [
        FactoryBot.create(
          :financial_assistance_applicant,
          family_member_id: family1.primary_family_member.id,
          first_name: person1.first_name,
          last_name: person1.last_name,
          gender: person1.gender,
          dob: person1.dob,
          person_hbx_id: person1.hbx_id,
          is_applying_coverage: true,
          is_primary_applicant: true
        )
      ]
    )
  end

  let(:application)   { FactoryBot.create(:individual_market_application, :prospective, family: family1) }
  let(:family_member) { application.family.family_members.first }
  let(:applicant) do
    FactoryBot.build(
      :individual_market_applicant,
      :with_person_name,
      :with_demographics,
      :with_eligibilities,
      :with_home_address,
      :with_phone_number,
      :with_email,
      application: application,
      family_member_id: family_member.id,
      is_primary_applicant: true
    )
  end
  let(:eligibility) { applicant.individual_market_eligibility }
  let(:determination) { FactoryBot.create(:individual_market_determination, :with_all_bases_satisfied, eligibility: eligibility) }

  describe '#call' do
    context 'when notice_type is oeg' do
      context 'when income_verification_only feature flag is enabled' do
        before :each do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:oeg_notice_income_verification_only).and_return(true)
        end

        context 'when most recent renewal FAA is in income verification extension' do
          let(:faa1_state) { 'income_verification_extension_required' }

          it 'triggers OEG notice' do
            faa1
            result = subject.call(notice_type: 'oeg')
            expect(result).to be_success
          end
        end
      end

      context 'when income_verification_only feature flag is disabled' do
        before :each do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:oeg_notice_income_verification_only).and_return(false)
        end

        context 'when most recent renewal FAA is in income_verification_extension_required state' do
          let(:faa1_state) { 'income_verification_extension_required' }

          it 'triggers OEG notice' do
            faa1
            result = subject.call(notice_type: 'oeg')
            expect(result).to be_success
          end
        end

        context 'when most recent renewal FAA is in renewal_draft state' do
          let(:faa1_state) { 'renewal_draft' }

          it 'triggers OEG notice' do
            faa1
            result = subject.call(notice_type: 'oeg')
            expect(result).to be_success
          end
        end
      end
    end

    context 'when notice_type is oeq' do
      before :each do
        benefit_sponsorship
        determination
      end

      it 'triggers OEQ notice' do
        result = subject.call(notice_type: 'oeq')
        expect(result).to be_success
      end
    end
  end
end
