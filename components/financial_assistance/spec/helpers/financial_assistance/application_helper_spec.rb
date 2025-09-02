# frozen_string_literal: true

require 'rails_helper'
RSpec.describe ::FinancialAssistance::ApplicationHelper, :type => :helper, dbclean: :after_each do
  include FinancialAssistance::Engine.routes.url_helpers

  let!(:application) { FactoryBot.create(:financial_assistance_application, family_id: BSON::ObjectId.new) }
  let!(:ed) { FactoryBot.create(:financial_assistance_eligibility_determination, application: application) }
  let!(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      application: application,
                      eligibility_determination_id: ed.id,
                      is_ia_eligible: true,
                      is_claimed_as_tax_dependent: false,
                      is_required_to_file_taxes: true,
                      first_name: 'Test',
                      last_name: 'Test10',
                      incomes: [job_income, net_self_employment_income, other_income],
                      deductions: [deduction])
  end

  let!(:applicant2) do
    FactoryBot.create(:financial_assistance_applicant,
                      application: application,
                      eligibility_determination_id: ed.id,
                      is_ia_eligible: true,
                      is_claimed_as_tax_dependent: true,
                      first_name: 'TEst2',
                      last_name: 'Test10')
  end

  let(:deduction) { FactoryBot.build(:financial_assistance_deduction) }
  let(:job_income) { FactoryBot.build(:financial_assistance_income, kind: FinancialAssistance::Income::JOB_INCOME_TYPE_KIND) }
  let(:net_self_employment_income) { FactoryBot.build(:financial_assistance_income, kind: FinancialAssistance::Income::NET_SELF_EMPLOYMENT_INCOME_KIND) }
  let(:other_income) { FactoryBot.build(:financial_assistance_income, kind: 'capital_gains') }

  describe 'claim_eligible_tax_dependents' do
    let!(:applicant3) do
      FactoryBot.create(:financial_assistance_applicant,
                        application: application,
                        eligibility_determination_id: ed.id,
                        is_ia_eligible: true,
                        is_claimed_as_tax_dependent: true,
                        first_name: 'TEst3',
                        last_name: 'Test10')
    end

    it "doesn't include is_claimed_as_tax_dependent true applicants (applicant 2)" do
      assign(:application, application)
      assign(:applicant, applicant3)
      expect(helper.claim_eligible_tax_dependents.map(&:first).flatten).to_not include("TEst2 Test10")
    end
  end

  describe 'total_aptc_across_eligibility_determinations' do
    before do
      @result = helper.total_aptc_across_eligibility_determinations(application.id)
    end

    it 'should return the sum of all aptcs' do
      expect(@result).to eq(225.13)
    end
  end

  describe 'eligible_applicants' do
    before do
      @result = helper.eligible_applicants(application.id, :is_ia_eligible)
    end

    it 'should return array of names of the applicants' do
      expect(@result).to include('Test Test10')
    end

    it 'should not return a split name if multiple capital letters exist' do
      expect(@result).to include('Test2 Test10')
    end
  end

  describe 'any_csr_ineligible_applicants?' do
    before do
      @result = helper.any_csr_ineligible_applicants?(application.id)
    end

    it 'should return false as the only applicant is eligible for CSR' do
      expect(@result).to be_falsy
    end
  end

  describe 'applicant_currently_enrolled' do
    context 'text for non hra setting is turned on' do
      before do
        allow(FinancialAssistanceRegistry[:has_enrolled_health_coverage].setting(:currently_enrolled)).to receive(:item).and_return(true)
        @result = helper.applicant_currently_enrolled
      end

      it 'should return non hra text' do
        expect(@result).to include('Is this person currently enrolled in health coverage?')
      end
    end

    context 'text for hra setting is turned on' do
      before do
        allow(FinancialAssistanceRegistry[:has_enrolled_health_coverage].setting(:currently_enrolled)).to receive(:item).and_return(false)
        allow(FinancialAssistanceRegistry[:has_enrolled_health_coverage].setting(:currently_enrolled_with_hra)).to receive(:item).and_return(true)
        @result = helper.applicant_currently_enrolled
      end

      it 'should return hra text' do
        expect(@result).to include('Is this person currently enrolled in health coverage or getting help paying for health coverage through a Health Reimbursement Arrangement?')
      end
    end

    context 'When both the settings are turned off' do
      before do
        allow(FinancialAssistanceRegistry[:has_enrolled_health_coverage].setting(:currently_enrolled)).to receive(:item).and_return(false)
        allow(FinancialAssistanceRegistry[:has_enrolled_health_coverage].setting(:currently_enrolled_with_hra)).to receive(:item).and_return(false)
        @result = helper.applicant_currently_enrolled
      end

      it 'should return nil' do
        expect(@result).to eq ''
      end
    end
  end

  describe 'applicant_currently_enrolled_key' do
    context 'text for non hra setting is turned on' do
      before do
        allow(FinancialAssistanceRegistry[:has_enrolled_health_coverage].setting(:currently_enrolled)).to receive(:item).and_return(true)
        @result = helper.applicant_currently_enrolled_key
      end

      it 'should return non hra key' do
        expect(@result).to eq 'has_enrolled_health_coverage'
      end
    end

    context 'text for hra setting is turned on' do
      before do
        allow(FinancialAssistanceRegistry[:has_enrolled_health_coverage].setting(:currently_enrolled)).to receive(:item).and_return(false)
        allow(FinancialAssistanceRegistry[:has_enrolled_health_coverage].setting(:currently_enrolled_with_hra)).to receive(:item).and_return(true)
        @result = helper.applicant_currently_enrolled_key
      end

      it 'should return hra key' do
        expect(@result).to eq 'has_enrolled_health_coverage_from_hra'
      end
    end

    context 'When both the settings are turned off' do
      before do
        allow(FinancialAssistanceRegistry[:has_enrolled_health_coverage].setting(:currently_enrolled)).to receive(:item).and_return(false)
        allow(FinancialAssistanceRegistry[:has_enrolled_health_coverage].setting(:currently_enrolled_with_hra)).to receive(:item).and_return(false)
        @result = helper.applicant_currently_enrolled_key
      end

      it 'should return nil' do
        expect(@result).to eq ''
      end
    end
  end

  describe 'applicant_eligibly_enrolled' do
    context 'text for non hra setting is turned on' do
      before do
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible)).to receive(:item).and_return(true)
        @result = helper.applicant_eligibly_enrolled
      end

      it 'should return non hra text' do
        expect(@result).to include('Does this person currently have access to other health coverage that they are not enrolled in, including coverage they could get through another person?')
      end
    end

    context 'text for hra setting is turned on' do
      before do
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible)).to receive(:item).and_return(false)
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible_with_hra)).to receive(:item).and_return(true)
        @result = helper.applicant_eligibly_enrolled
      end

      it 'should return hra text' do
        expect(@result).to include('Does this person currently have access to health coverage or a Health Reimbursement Arrangement that they are not enrolled in (including through another person, like a spouse or parent)?')
      end
    end

    context 'text for hra setting is turned on and minimum_value_standard_question enabled' do
      before do
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible)).to receive(:item).and_return(false)
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible_with_hra)).to receive(:item).and_return(true)
        allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:minimum_value_standard_question).and_return(true)
        @result = helper.applicant_eligibly_enrolled
      end

      it 'should return hra text without the parentheses' do
        expect(@result).to include('Does this person currently have access to health coverage or a Health Reimbursement Arrangement that they are not enrolled in?')
      end
    end

    context 'When both the settings are turned off' do
      before do
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible)).to receive(:item).and_return(false)
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible_with_hra)).to receive(:item).and_return(false)
        @result = helper.applicant_eligibly_enrolled
      end

      it 'should return nil' do
        expect(@result).to eq ''
      end
    end
  end

  describe 'applicant_eligibly_enrolled_key' do
    context 'text for non hra setting is turned on' do
      before do
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible)).to receive(:item).and_return(true)
        @result = helper.applicant_eligibly_enrolled_key
      end

      it 'should return non hra key' do
        expect(@result).to eq 'has_eligible_health_coverage'
      end
    end

    context 'text for hra setting is turned on' do
      before do
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible)).to receive(:item).and_return(false)
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible_with_hra)).to receive(:item).and_return(true)
        @result = helper.applicant_eligibly_enrolled_key
      end

      it 'should return hra key' do
        expect(@result).to eq 'has_eligible_health_coverage_from_hra'
      end
    end

    context 'When both the settings are turned off' do
      before do
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible)).to receive(:item).and_return(false)
        allow(FinancialAssistanceRegistry[:has_eligible_health_coverage].setting(:currently_eligible_with_hra)).to receive(:item).and_return(false)
        @result = helper.applicant_eligibly_enrolled_key
      end

      it 'should return nil when both the settings are turned off' do
        expect(@result).to eq ''
      end
    end
  end

  context 'csr_73_87_or_94_eligible_applicants' do
    before do
      applicant.update_attributes!({ is_ia_eligible: true, csr_percent_as_integer: [73, 87, 94].sample })
      applicant.reload
      @result = helper.csr_73_87_or_94_eligible_applicants?(application.id)
    end

    it "should return applicant's full name" do
      expect(@result).to include(applicant.full_name)
    end
  end

  context 'csr_100_eligible_applicants' do
    before do
      applicant.update_attributes!({ is_ia_eligible: true, csr_percent_as_integer: 100 })
      applicant.reload
      @result = helper.csr_100_eligible_applicants?(application.id)
    end

    it "should return applicant's full name" do
      expect(@result).to include(applicant.full_name)
    end
  end

  context 'csr_limited_eligible_applicants' do
    context 'aqhp' do
      before do
        applicant.update_attributes!({ is_ia_eligible: true, csr_percent_as_integer: -1 })
        applicant.reload
        @result = helper.csr_limited_eligible_applicants?(application.id)
      end

      it "should return applicant's full name" do
        expect(@result).to include(applicant.full_name)
      end
    end

    context 'uqhp' do
      before do
        applicant.update_attributes!({ indian_tribe_member: true })
        applicant.reload
        @result = helper.csr_limited_eligible_applicants?(application.id)
      end

      it "should return applicant's full name" do
        expect(@result).to include(applicant.full_name)
      end
    end
  end

  context '#fetch_counties_by_zip', dbclean: :after_each do
    let!(:county) {BenefitMarkets::Locations::CountyZip.create(zip: "04642", county_name: "Hancock")}

    context 'for 9 digit zip' do
      it "should return county" do
        applicant.addresses.create(zip: "04642-3116", county: 'Hancock', state: 'ME')
        address = applicant.addresses.first
        result = helper.fetch_counties_by_zip(address)
        expect(result).to eq ['Hancock']
      end
    end

    context 'for 5 digit zip' do
      it "should return county" do
        applicant.addresses.create(zip: "04642", county: 'Hancock', state: 'ME')
        address = applicant.addresses.first
        result = helper.fetch_counties_by_zip(address)
        expect(result).to eq ['Hancock']
      end
    end

    context 'for nil address' do
      it "should return empty array" do
        result = helper.fetch_counties_by_zip(nil)
        expect(result).to eq []
      end
    end

    context 'for nil zip' do
      it "should return empty array" do
        applicant.addresses.update_all(zip: nil, county: 'Hancock')
        address = applicant.addresses.first
        result = helper.fetch_counties_by_zip(address)
        expect(result).to eq []
      end
    end
  end

  describe '#full_name' do
    it 'should return name' do
      expect(helper.full_name(applicant)).to eq('Test Test10')
    end
  end

  describe '#display_csr' do
    context 'csr eligible for 94, 87, 73, 100' do
      let(:csr_kind) { ['csr_94', 'csr_87', 'csr_73', 'csr_100'].sample }

      it 'should return displayable csr' do
        applicant.csr_eligibility_kind = csr_kind
        applicant.save!
        expect(helper.display_csr(applicant.reload)).to eq("#{csr_kind.split('_').last}%")
      end
    end

    context 'csr_limited' do
      it 'should return displayable csr' do
        applicant.csr_eligibility_kind = 'csr_limited'
        applicant.save!
        expect(helper.display_csr(applicant.reload)).to eq('Limited')
      end
    end
  end

  describe '#prospective_year_application?' do
    let(:system_year) { TimeKeeper.date_of_record.year }
    let(:application_stub) { OpenStruct.new(assistance_year: application_year) }
    let(:current_user) { OpenStruct.new(has_hbx_staff_role?: false) }
    let(:current_hbx_profile) { OpenStruct.new(under_open_enrollment?: open_enrollment) }

    before do
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:block_prospective_year_application_copy_before_oe).and_return(enabled)
      allow(HbxProfile).to receive(:current_hbx).and_return(current_hbx_profile)
    end

    context 'configuration is turned OFF' do
      let(:enabled) { false }
      let(:open_enrollment) { false }
      let(:application_year) { system_year }

      it 'should return false as feature is turned OFF' do
        expect(helper.prospective_year_application?(application_stub)).to eq(false)
      end
    end

    context 'configuration is turned ON and is under open_enrollment' do
      let(:enabled) { true }
      let(:open_enrollment) { true }
      let(:application_year) { system_year }

      it 'should return false as system is under open_enrollment' do
        expect(helper.prospective_year_application?(application_stub)).to eq(false)
      end
    end

    context 'configuration turned ON, not under open_enrollment, prospective_year_application' do
      let(:enabled) { true }
      let(:open_enrollment) { false }
      let(:application_year) { system_year.next }

      it 'should return false as system is under open_enrollment' do
        expect(helper.prospective_year_application?(application_stub)).to eq(true)
      end
    end

    context 'configuration turned ON, under open_enrollment, current_year_application' do
      let(:enabled) { true }
      let(:open_enrollment) { true }
      let(:application_year) { system_year }

      it 'should return false as system is under open_enrollment' do
        expect(helper.prospective_year_application?(application_stub)).to eq(false)
      end
    end

    context 'configuration turned ON, not under open_enrollment, application without application_year' do
      let(:enabled) { true }
      let(:open_enrollment) { false }
      let(:application_year) { nil }

      it 'should return false as system is under open_enrollment' do
        expect(helper.prospective_year_application?(application_stub)).to eq(false)
      end
    end
  end

  describe '#display_minimum_value_standard_question?' do
    before do
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:minimum_value_standard_question).and_return(enabled)
    end

    context 'RR configuration turned OFF' do
      let(:enabled) { false }
      let(:insurance_kind) { 'health_reimbursement_arrangement' }

      it 'should return false' do
        expect(
          helper.display_minimum_value_standard_question?(insurance_kind)
        ).to eq(false)
      end
    end

    context 'RR configuration turned ON, insurance_kind: health_reimbursement_arrangement' do
      let(:enabled) { true }
      let(:insurance_kind) { 'health_reimbursement_arrangement' }

      it 'should return false' do
        expect(
          helper.display_minimum_value_standard_question?(insurance_kind)
        ).to eq(false)
      end
    end

    context 'RR configuration turned ON, insurance_kind: employer_sponsored_insurance' do
      let(:enabled) { true }
      let(:insurance_kind) { 'employer_sponsored_insurance' }

      it 'should return true' do
        expect(
          helper.display_minimum_value_standard_question?(insurance_kind)
        ).to eq(true)
      end
    end
  end

  describe '#display_esi_fields?' do
    before do
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:short_enrolled_esi_forms).and_return(enabled)
    end

    context 'RR configuration turned OFF' do
      let(:enabled) { false }
      let(:insurance_kind) { 'health_reimbursement_arrangement' }

      it 'should return true if enrolled' do
        expect(
          helper.display_esi_fields?(insurance_kind, 'is_enrolled')
        ).to eq(true)
      end

      it 'should return true if eligible' do
        expect(
          helper.display_esi_fields?(insurance_kind, 'is_eligible')
        ).to eq(true)
      end
    end

    context 'RR configuration turned ON' do
      let(:enabled) { true }
      let(:insurance_kind) { 'employer_sponsored_insurance' }

      it 'should return false if enrolled' do
        expect(
          helper.display_esi_fields?(insurance_kind, 'is_enrolled')
        ).to eq(false)
      end

      it 'should return true if eligible' do
        expect(
          helper.display_esi_fields?(insurance_kind, 'is_eligible')
        ).to eq(true)
      end
    end
  end

  describe 'sanitize_insurance_kind' do
    before do
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:remove_cubcare_references).and_return(true)
    end

    it 'should return medicaid when the insurance_kind is chip' do
      expect(helper.sanitize_insurance_kind('child_health_insurance_plan').downcase).to include('medicaid')
      expect(helper.sanitize_insurance_kind('child_health_insurance_plan').downcase).not_to include('child_health_insurance_plan')
    end
  end

  describe '#calculate_step_number' do
    let!(:single_applicant_app) { FactoryBot.create(:financial_assistance_application, family_id: BSON::ObjectId.new) }
    let!(:ed) { FactoryBot.create(:financial_assistance_eligibility_determination, application: single_applicant_app) }
    let!(:single_applicant) do
      FactoryBot.create(:financial_assistance_applicant,
                        application: single_applicant_app,
                        eligibility_determination_id: ed.id,
                        is_ia_eligible: true,
                        is_claimed_as_tax_dependent: false,
                        is_required_to_file_taxes: true,
                        first_name: 'Test',
                        last_name: 'Test10')
    end

    context 'when QHP feature is enabled' do
      before do
        allow(helper).to receive(:qhp_application_feature_enabled?).and_return(true)
      end

      context 'with a single applicant' do
        it 'returns step 6 for eligibility results page' do
          expect(helper.calculate_step_number(single_applicant_app, 'eligibility_results_page')).to eq 6
        end

        it 'returns step 5 for submit page' do
          expect(helper.calculate_step_number(single_applicant_app, 'submit_page')).to eq 5
        end

        it 'returns step 4 for review page' do
          expect(helper.calculate_step_number(single_applicant_app, 'review_page')).to eq 4
        end

        it 'returns step 3 for preferences page' do
          expect(helper.calculate_step_number(single_applicant_app, 'preferences_page')).to eq 3
        end

        it 'returns step 2 for income page' do
          expect(helper.calculate_step_number(single_applicant_app, 'income_page')).to eq 2
        end
      end

      context 'with multiple applicants' do
        it 'returns step 7 for eligibility results page' do
          expect(helper.calculate_step_number(application, 'eligibility_results_page')).to eq 7
        end

        it 'returns step 6 for submit page' do
          expect(helper.calculate_step_number(application, 'submit_page')).to eq 6
        end

        it 'returns step 5 for review page' do
          expect(helper.calculate_step_number(application, 'review_page')).to eq 5
        end

        it 'returns step 4 for preferences page' do
          expect(helper.calculate_step_number(application, 'preferences_page')).to eq 4
        end

        it 'returns step 3 for income page' do
          expect(helper.calculate_step_number(application, 'income_page')).to eq 3
        end
      end
    end

    context 'when QHP feature is disabled' do
      before do
        allow(helper).to receive(:qhp_application_feature_enabled?).and_return(false)
      end

      context 'with a single applicant' do
        it 'returns step 2 for eligibility results page' do
          expect(helper.calculate_step_number(single_applicant_app, 'eligibility_results_page')).to eq 2
        end

        it 'returns step 2 for submit page' do
          expect(helper.calculate_step_number(single_applicant_app, 'submit_page')).to eq 2
        end

        it 'returns step 2 for review page' do
          expect(helper.calculate_step_number(single_applicant_app, 'review_page')).to eq 2
        end

        it 'returns step 2 for preferences page' do
          expect(helper.calculate_step_number(single_applicant_app, 'preferences_page')).to eq 2
        end

        it 'returns step 1 for income page' do
          expect(helper.calculate_step_number(single_applicant_app, 'income_page')).to eq 1
        end
      end

      context 'with multiple applicants' do
        it 'returns step 3 for eligibility results page' do
          expect(helper.calculate_step_number(application, 'eligibility_results_page')).to eq 3
        end

        it 'returns step 3 for submit page' do
          expect(helper.calculate_step_number(application, 'submit_page')).to eq 3
        end

        it 'returns step 3 for review page' do
          expect(helper.calculate_step_number(application, 'review_page')).to eq 3
        end

        it 'returns step 3 for preferences page' do
          expect(helper.calculate_step_number(application, 'preferences_page')).to eq 3
        end

        it 'returns step 1 for income page' do
          expect(helper.calculate_step_number(application, 'income_page')).to eq 1
        end
      end
    end

    context 'with an invalid page title' do
      it 'returns nil' do
        allow(helper).to receive(:qhp_application_feature_enabled?).and_return(true)
        expect(helper.calculate_step_number(application, 'invalid_page')).to be_nil
      end
    end
  end

  describe "#personal_info_rows" do
    context "when qhp_application_feature is enabled" do
      before do
        allow(helper).to receive(:qhp_application_feature_enabled?).and_return(true)
      end

      it "returns the full set of attributes" do
        expected_attributes = [
          :dob, :gender, :ssn_provided, :relationship, :status, :coverage, :us_citizen,
          :naturalized_citizen, :eligible, :american_indian_or_alaska_native_tribe,
          :is_incarcerated, :age_off_excluded
        ].freeze

        expect(helper.personal_info_rows('AnyClass')).to eq(expected_attributes)
      end

      it "returns a frozen array" do
        expect(helper.personal_info_rows('AnyClass')).to be_frozen
      end
    end

    context "when qhp_application_feature is disabled" do
      before do
        allow(helper).to receive(:qhp_application_feature_enabled?).and_return(false)
      end

      it "returns consumer-specific attributes for ConsumerApplicantSummary" do
        expected_attributes = [
          :age, :gender, :relationship, :status, :is_incarcerated, :coverage
        ].freeze

        expect(helper.personal_info_rows('ConsumerApplicantSummary')).to eq(expected_attributes)
      end

      it "returns admin-specific attributes for AdminApplicantSummary" do
        expected_attributes = [
          :dob, :gender, :relationship, :coverage
        ].freeze

        expect(helper.personal_info_rows('AdminApplicantSummary')).to eq(expected_attributes)
      end

      it "returns frozen arrays" do
        expect(helper.personal_info_rows('ConsumerApplicantSummary')).to be_frozen
        expect(helper.personal_info_rows('AdminApplicantSummary')).to be_frozen
      end

      it "returns nil for unhandled class names" do
        expect(helper.personal_info_rows('UnhandledClassName')).to be_nil
      end
    end
  end

  describe '#do_not_allow_copy?' do
    let(:copyable_application_ids) { [1, 2, 3, 4] }

    let(:input_app) do
      double(
        'FinancialAssistance::Application',
        assistance_year: TimeKeeper.date_of_record.year,
        id: app_id,
        determined?: determined
      )
    end

    let(:app_id) { 1 }

    let(:determined) { true }

    context 'logged in user is not an hbx_admin' do
      let(:person) { FactoryBot.create(:person, :with_consumer_role) }
      let(:user) { FactoryBot.create(:user, person: person) }

      context 'application is not in the copyable list' do
        let(:app_id) { 5 }

        it 'returns true' do
          expect(
            helper.do_not_allow_copy?(input_app, user, copyable_application_ids)
          ).to be_truthy
        end
      end

      context 'application is in the copyable list' do
        it 'returns false' do
          expect(
            helper.do_not_allow_copy?(input_app, user, copyable_application_ids)
          ).to be_falsy
        end
      end
    end

    context 'logged in user is an hbx_admin' do
      let(:person) { FactoryBot.create(:person, :with_consumer_role) }
      let(:user) { FactoryBot.create(:user, person: person) }

      before do
        FactoryBot.create(:hbx_staff_role, person: person)
      end

      context 'application is in determined state' do
        it 'returns false' do
          expect(
            helper.do_not_allow_copy?(input_app, user, copyable_application_ids)
          ).to be_falsy
        end
      end

      context 'application is not in determined state' do
        let(:determined) { false }

        it 'returns true' do
          expect(
            helper.do_not_allow_copy?(input_app, user, copyable_application_ids)
          ).to be_truthy
        end
      end
    end
  end

  describe '#income_and_deductions_edit' do
    subject { helper.income_and_deductions_edit(application, applicant, embedded_document) }

    context 'when QHP feature is enabled and application is reviewable' do
      before do
        allow(helper).to receive(:qhp_application_feature_enabled?).and_return(true)
        allow(application).to receive(:is_reviewable?).and_return(true)
      end

      context 'with Deduction document' do
        let(:embedded_document) { deduction }

        it 'returns copy_application_path with income_adjustments param' do
          expected_path = financial_assistance.copy_application_path(
            application,
            applicant: applicant.id,
            applicant_hbx_id: applicant.person_hbx_id,
            income_adjustments: true
          )
          expect(subject).to eq(expected_path)
        end
      end

      context 'with Job Income document' do
        let(:embedded_document) { job_income }

        it 'returns copy_application_path with income param' do
          expected_path = financial_assistance.copy_application_path(
            application,
            applicant: applicant.id,
            applicant_hbx_id: applicant.person_hbx_id,
            income: true
          )
          expect(subject).to eq(expected_path)
        end
      end

      context 'with Other Income document' do
        let(:embedded_document) { other_income }

        it 'returns copy_application_path with other_questions param' do
          expected_path = financial_assistance.copy_application_path(
            application,
            applicant: applicant.id,
            applicant_hbx_id: applicant.person_hbx_id,
            other_incomes: true
          )
          expect(subject).to eq(expected_path)
        end
      end
    end

    context 'when QHP feature is disabled or application is not reviewable' do
      before do
        allow(helper).to receive(:qhp_application_feature_enabled?).and_return(false)
        allow(application).to receive(:is_reviewable?).and_return(false)
      end

      context 'with Deduction document' do
        let(:embedded_document) { deduction }

        it 'returns application_applicant_deductions_path' do
          expected_path = financial_assistance.application_applicant_deductions_path(application, applicant)
          expect(subject).to eq(expected_path)
        end
      end

      context 'with Job Income document' do
        let(:embedded_document) { job_income }

        it 'returns application_applicant_incomes_path' do
          expected_path = financial_assistance.application_applicant_incomes_path(application, applicant)
          expect(subject).to eq(expected_path)
        end
      end

      context 'with Other Income document' do
        let(:embedded_document) { other_income }

        it 'returns other_application_applicant_incomes_path' do
          expected_path = financial_assistance.other_application_applicant_incomes_path(application, applicant)
          expect(subject).to eq(expected_path)
        end
      end
    end
  end

  describe '#job_or_self_employment_income?' do
    it 'returns true for job income kind' do
      expect(helper.send(:job_or_self_employment_income?, job_income)).to be true
    end

    it 'returns true for net self-employment income kind' do
      expect(helper.send(:job_or_self_employment_income?, net_self_employment_income)).to be true
    end

    it 'returns false for other income kind' do
      expect(helper.send(:job_or_self_employment_income?, other_income)).to be false
    end
  end

  describe 'applicant_faa_nav_options' do
    let!(:family) { FactoryBot.create(:family, :with_primary_family_member) }
    let!(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: 'draft') }
    let!(:ed) { FactoryBot.create(:financial_assistance_eligibility_determination, application: application) }
    let!(:applicant) do
      FactoryBot.create(:financial_assistance_applicant,
                        application: application,
                        eligibility_determination_id: ed.id,
                        is_ia_eligible: true,
                        is_claimed_as_tax_dependent: false,
                        is_required_to_file_taxes: true,
                        first_name: 'Test',
                        last_name: 'User')
    end

    before do
      helper.class.class_eval do
        def go_to_step_application_applicant_path(*args); end

        def application_applicant_incomes_path(*args); end

        def other_application_applicant_incomes_path(*args); end

        def application_applicant_deductions_path(*args); end

        def application_applicant_benefits_path(*args); end

        def other_questions_application_applicant_path(*args); end
      end

      allow(helper).to receive(:go_to_step_application_applicant_path).and_return('tax_info_path')
      allow(helper).to receive(:application_applicant_incomes_path).and_return('job_income_path')
      allow(helper).to receive(:other_application_applicant_incomes_path).and_return('other_income_path')
      allow(helper).to receive(:application_applicant_deductions_path).and_return('income_adjustments_path')
      allow(helper).to receive(:application_applicant_benefits_path).and_return('health_coverage_path')
      allow(helper).to receive(:other_questions_application_applicant_path).and_return('other_questions_path')


      allow(applicant).to receive(:tax_info_complete?).and_return(true)
      allow(applicant).to receive(:embedded_document_section_entry_complete?).and_return(false)
      allow(applicant).to receive(:other_questions_complete?).and_return(false)
    end

    context 'when the applicant is applying for coverage' do
      before do
        applicant.update_attributes!(is_applying_coverage: true)
      end

      let(:nav_options) { helper.applicant_faa_nav_options(application, applicant) }

      it 'returns a total of 6 navigation steps' do
        expect(nav_options.count).to eq(6)
      end

      it 'includes the "Health Coverage" step as step 5' do
        health_coverage_step = nav_options.find { |opt| opt[:label] == 'Health Coverage' }
        expect(health_coverage_step).to be_present
        expect(health_coverage_step[:step]).to eq(5)
        expect(health_coverage_step[:link]).to eq('health_coverage_path')
      end

      it 'includes the "Other Questions" step as step 6' do
        other_questions_step = nav_options.find { |opt| opt[:label] == 'Other Questions' }
        expect(other_questions_step).to be_present
        expect(other_questions_step[:step]).to eq(6)
        expect(other_questions_step[:link]).to eq('other_questions_path')
      end

      it 'builds the first step correctly' do
        tax_info_step = nav_options.first
        expect(tax_info_step[:step]).to eq(1)
        expect(tax_info_step[:label]).to eq('Tax Info')
        expect(tax_info_step[:link]).to eq('tax_info_path')
        expect(tax_info_step[:step_complete]).to be true
      end
    end

    context 'when the applicant is NOT applying for coverage' do
      before do
        applicant.update_attributes!(is_applying_coverage: false)
      end

      let(:nav_options) { helper.applicant_faa_nav_options(application, applicant) }

      it 'returns a total of 5 navigation steps' do
        expect(nav_options.count).to eq(5)
      end

      it 'does NOT include the "Health Coverage" step' do
        health_coverage_step = nav_options.find { |opt| opt[:label] == 'Health Coverage' }
        expect(health_coverage_step).to be_nil
      end

      it 'includes the "Other Questions" step as step 5' do
        other_questions_step = nav_options.find { |opt| opt[:label] == 'Other Questions' }
        expect(other_questions_step).to be_present
        expect(other_questions_step[:step]).to eq(5)
        expect(other_questions_step[:link]).to eq('other_questions_path')
      end
    end
  end

  describe '#faa_nav_options' do
    let!(:family) { FactoryBot.create(:family, :with_primary_family_member) }
    let!(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: 'draft') }
    let!(:ed) { FactoryBot.create(:financial_assistance_eligibility_determination, application: application) }
    let!(:applicant) do
      FactoryBot.create(:financial_assistance_applicant,
                        application: application,
                        eligibility_determination_id: ed.id,
                        is_ia_eligible: true,
                        is_claimed_as_tax_dependent: false,
                        is_required_to_file_taxes: true,
                        first_name: 'Test',
                        last_name: 'User')
    end

    before do
      allow(helper).to receive(:l10n).and_call_original
      allow(helper).to receive(:financial_assistance).and_return(double)
      allow(helper.financial_assistance).to receive(:application_applicants_path).and_return('/path/to/applicants')
      allow(helper.financial_assistance).to receive(:edit_application_path).and_return('/path/to/edit')
      allow(helper.financial_assistance).to receive(:applications_path).and_return('/path/to/applications')
      allow(helper.financial_assistance).to receive(:application_relationships_path).and_return('/path/to/relationships')
      allow(helper.financial_assistance).to receive(:preferences_application_path).and_return('/path/to/preferences')
      allow(helper.financial_assistance).to receive(:review_and_submit_application_path).and_return('/path/to/review')
      allow(helper.financial_assistance).to receive(:submit_your_application_application_path).and_return('/path/to/submit')
      allow(helper).to receive(:applicant_faa_nav_options).and_return([
        {step: 1, label: 'Tax Info', link: '/tax-info', step_complete: true},
        {step: 2, label: 'Job Income', link: '/job-income', step_complete: false}
      ])
      allow(helper).to receive(:no_applicant_faa_nav_options).and_return([
        {step: 1, label: 'Family Info', link: '/family-info'},
        {step: 2, label: 'Review', link: '/review'}
      ])
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:back_to_account_all_shop).and_return(true)
      allow(family).to receive(:eligibility_determination?).and_return(true)
      allow(application).to receive(:family).and_return(family)
    end

    context 'when applicant is present' do
      let(:step) { 2 }

      context 'when QHP feature is enabled' do
        before do
          allow(helper).to receive(:qhp_application_feature_enabled?).and_return(true)
        end

        it 'returns correct navigation structure' do
          result = helper.faa_nav_options(step, application, applicant)

          expect(result[:nav_options]).to eq([
            {step: 1, label: 'Tax Info', link: '/tax-info', step_complete: true},
            {step: 2, label: 'Job Income', link: '/job-income', step_complete: false}
          ])
          expect(result[:links]).to be true
          expect(result[:step]).to eq step
          expect(result[:title]).to eq helper.l10n("faa.nav.my_household")
          expect(result[:title_link]).to eq '/path/to/applicants'
          expect(result[:subheading]).to be_nil
          expect(result[:show_help_button]).to be true
          expect(result[:show_exit_button]).to be true
          expect(result[:show_previous_button]).to be false
          expect(result[:show_account_button]).to be true
          expect(result[:back_to_account_flag]).to be true
        end
      end

      context 'when QHP feature is disabled' do
        before do
          allow(helper).to receive(:qhp_application_feature_enabled?).and_return(false)
        end

        context 'when application is draft' do
          it 'returns correct navigation structure with my_household title' do
            result = helper.faa_nav_options(step, application, applicant)

            expect(result[:nav_options]).to eq([
              {step: 1, label: 'Tax Info', link: '/tax-info', step_complete: true},
              {step: 2, label: 'Job Income', link: '/job-income', step_complete: false}
            ])
            expect(result[:title]).to eq helper.l10n("faa.nav.my_household")
            expect(result[:title_link]).to eq '/path/to/edit'
            expect(result[:subheading]).to eq helper.l10n("faa.nav.applicant_subheader")
          end
        end

        context 'when application is not draft' do
          before do
            allow(application).to receive(:is_draft?).and_return(false)
          end

          it 'returns correct navigation structure with applications title' do
            result = helper.faa_nav_options(step, application, applicant)

            expect(result[:title]).to eq helper.l10n("faa.results.view_my_applications").titleize
            expect(result[:title_link]).to eq '/path/to/applications'
          end
        end
      end
    end

    context 'when applicant is not present' do
      let(:step) { 1 }
      let(:applicant) { nil }

      context 'when QHP feature is enabled' do
        before do
          allow(helper).to receive(:qhp_application_feature_enabled?).and_return(true)
        end

        it 'returns correct navigation structure' do
          result = helper.faa_nav_options(step, application, applicant)

          expect(result[:nav_options]).to eq([
            {step: 1, label: 'Family Info', link: '/family-info'},
            {step: 2, label: 'Review', link: '/review'}
          ])
          expect(result[:links]).to be true
          expect(result[:step]).to eq step
          expect(result[:title]).to eq helper.l10n("faa.nav.enroll_in_coverage")
          expect(result[:title_link]).to be_nil
          expect(result[:subheading]).to be_nil
        end
      end

      context 'when QHP feature is disabled' do
        before do
          allow(helper).to receive(:qhp_application_feature_enabled?).and_return(false)
        end

        context 'when step is 1 and application is draft' do
          it 'returns view_my_applications title' do
            result = helper.faa_nav_options(step, application, applicant)

            expect(result[:title]).to eq helper.l10n("faa.results.view_my_applications").titleize
            expect(result[:title_link]).to eq '/path/to/applications'
            expect(result[:subheading]).to eq helper.l10n("faa.nav.applicant_subheader")
          end
        end

        context 'when step is not 1' do
          let(:step) { 2 }

          it 'returns my_household title' do
            result = helper.faa_nav_options(step, application, applicant)

            expect(result[:title]).to eq helper.l10n("faa.nav.my_household")
            expect(result[:title_link]).to eq '/path/to/edit'
          end
        end
      end
    end

    context 'when back_to_account feature is disabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:back_to_account_all_shop).and_return(false)
        allow(helper).to receive(:qhp_application_feature_enabled?).and_return(true)
      end

      it 'sets show_account_button to false' do
        result = helper.faa_nav_options(1, application, applicant)

        expect(result[:show_account_button]).to be false
      end
    end

    context 'when family does not have eligibility determination' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:back_to_account_all_shop).and_return(true)
        allow(family).to receive(:eligibility_determination?).and_return(false)
        allow(helper).to receive(:qhp_application_feature_enabled?).and_return(true)
      end

      it 'sets show_account_button to false' do
        result = helper.faa_nav_options(1, application, applicant)

        expect(result[:show_account_button]).to be false
      end
    end
  end
end
