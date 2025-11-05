# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::Eligibilities::FamilyEvidencesDataExportV3,
               type: :model,
               dbclean: :after_each do
  let!(:person1) do
    FactoryBot.create(
      :person,
      :with_consumer_role,
      :with_active_consumer_role,
      first_name: 'John',
      last_name: 'Doe',
      gender: 'male'
    )
  end

  let!(:person2) do
    person = FactoryBot.create(
      :person,
      :with_consumer_role,
      :with_active_consumer_role,
      first_name: 'Jane',
      last_name: 'Doe',
      gender: 'female'
    )
    person1.ensure_relationship_with(person, 'spouse')
    person
  end

  let!(:family) do
    FactoryBot.create(:family, :with_primary_family_member, person: person1)
  end

  let!(:family_member2) do
    FactoryBot.create(:family_member, family: family, person: person2)
  end

  let(:assistance_year) { TimeKeeper.date_of_record.year }
  let(:operation) { described_class.new }

  before do
    DatabaseCleaner.clean
  end

  describe '#call' do
    context 'with valid inputs' do
      let(:params) do
        {
          family: family,
          assistance_year: assistance_year
        }
      end

      it 'returns Success monad' do
        result = operation.call(params)
        expect(result).to be_success
      end

      it 'returns array of family member data arrays' do
        result = operation.call(params).success
        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        expect(result.first).to be_an(Array)
        expect(result.last).to be_an(Array)
      end

      it 'returns arrays with correct column count' do
        result = operation.call(params).success
        expected_column_count = operation.send(:ordered_column_keys).length

        result.each do |family_member_row|
          expect(family_member_row.length).to eq(expected_column_count)
        end
      end

      it 'includes basic family data in correct positions' do
        result = operation.call(params).success
        primary_member_row = result.first

        expect(primary_member_row[0]).to eq(family.hbx_assigned_id)
        expect(primary_member_row[1]).to eq(family.primary_person.hbx_id)
        expect(primary_member_row[2]).to be(true)
        expect(primary_member_row[3]).to eq(person1.hbx_id)
        expect(primary_member_row[4]).to eq(person1.ssn)
        expect(primary_member_row[5]).to eq(person1.first_name)
        expect(primary_member_row[6]).to eq(person1.last_name)
        expect(primary_member_row[7]).to be(true)
      end

      it 'correctly identifies primary vs non-primary members' do
        result = operation.call(params).success
        primary_row = result.first
        spouse_row = result.last

        expect(primary_row[2]).to be(true)
        expect(spouse_row[2]).to be(false)
      end
    end

    context 'with invalid inputs' do
      context 'when family is missing' do
        let(:params) { { assistance_year: assistance_year } }

        it 'returns Failure with error message' do
          result = operation.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq('family missing')
        end
      end

      context 'when assistance_year is missing' do
        let(:params) { { family: family } }

        it 'returns Failure with error message' do
          result = operation.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq('assistance year missing')
        end
      end

      context 'when family is not a Family object' do
        let(:params) do
          {
            family: 'not_a_family',
            assistance_year: assistance_year
          }
        end

        it 'returns Failure with error message' do
          result = operation.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq('family missing')
        end
      end

      context 'when family is nil' do
        let(:params) do
          {
            family: nil,
            assistance_year: assistance_year
          }
        end

        it 'returns Failure with error message' do
          result = operation.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq('family missing')
        end
      end
    end
  end

  describe '#ordered_column_keys' do
    it 'returns complete list of column keys in correct order' do
      keys = operation.send(:ordered_column_keys)

      expect(keys).to be_an(Array)
      expect(keys.length).to eq(51)
      expect(keys.first).to eq(:family_hbx_id)
      expect(keys[1]).to eq(:primary_hbx_id)
      expect(keys[2]).to eq(:is_subscriber)
      expect(keys).to include(:member_hbx_id, :ssn, :member_first_name, :member_last_name)
      expect(keys).to include(:health_cov_hbx_id, :dental_cov_hbx_id)
      expect(keys).to include(:citizen_kind, :immigrant_kind)
      expect(keys).to include(:aptc_amt, :csr)
      expect(keys).to include(:application_hbx_id, :applicant_applying_coverage)
      expect(keys).to include(:income_status, :income_due_date, :income_auto_extended, :income_response)
      expect(keys).to include(:esi_status, :non_esi_status, :local_mec_status)
    end
  end

  describe '#latest_application' do
    before do
      operation.instance_variable_set(:@family, family)
      operation.instance_variable_set(:@assistance_year, assistance_year)
    end

    context 'when no applications exist' do
      it 'returns nil' do
        result = operation.send(:latest_application)
        expect(result).to be_nil
      end
    end

    context 'when only individual market application exists' do
      let!(:im_application) do
        FactoryBot.create(
          :individual_market_application,
          family: family,
          current_state: :determined,
          assistance_year: assistance_year,
          submitted_at: Time.current
        )
      end

      it 'returns the individual market application' do
        result = operation.send(:latest_application)
        expect(result).to eq(im_application)
      end
    end

    context 'when only financial assistance application exists' do
      let!(:fa_application) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: assistance_year,
          aasm_state: 'determined',
          submitted_at: Time.current
        )
      end

      it 'returns the financial assistance application' do
        result = operation.send(:latest_application)
        expect(result).to eq(fa_application)
      end
    end

    context 'when both application types exist' do
      let!(:fa_application) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: assistance_year,
          aasm_state: 'determined',
          submitted_at: Time.current
        )
      end

      let!(:im_application) do
        FactoryBot.create(
          :individual_market_application,
          current_state: :determined,
          family: family,
          assistance_year: assistance_year,
          submitted_at: Time.current + 1.hour
        )
      end

      it 'returns the most recently submitted application' do
        result = operation.send(:latest_application)
        expect(result).to eq(im_application)
      end
    end
  end

  describe '#validate' do
    let(:operation) { described_class.new }

    context 'when all required params are valid' do
      let(:params) do
        {
          family: family,
          assistance_year: assistance_year
        }
      end

      it 'returns Success and sets instance variables' do
        result = operation.send(:validate, params)
        expect(result).to be_success
        expect(operation.instance_variable_get(:@family)).to eq(family)
        expect(operation.instance_variable_get(:@assistance_year)).to eq(assistance_year)
      end
    end

    context 'when family param is invalid' do
      let(:params) do
        {
          family: 'invalid',
          assistance_year: assistance_year
        }
      end

      it 'returns Failure' do
        result = operation.send(:validate, params)
        expect(result).to be_failure
        expect(result.failure).to eq('family missing')
      end
    end

    context 'when assistance_year param is missing' do
      let(:params) { { family: family } }

      it 'returns Failure' do
        result = operation.send(:validate, params)
        expect(result).to be_failure
        expect(result.failure).to eq('assistance year missing')
      end
    end
  end

  describe '#construct_family_data' do
    before do
      operation.instance_variable_set(:@family, family)
      operation.instance_variable_set(:@assistance_year, assistance_year)
    end

    it 'returns Success with array of family member data' do
      result = operation.send(:construct_family_data)
      expect(result).to be_success
      expect(result.success).to be_an(Array)
      expect(result.success.length).to eq(2)
    end

    it 'constructs data for each active family member' do
      allow(operation).to receive(:get_basic_family_data).and_return({})
      allow(operation).to receive(:get_person_data).and_return({})
      allow(operation).to receive(:get_family_member_coverage_details).and_return({})
      allow(operation).to receive(:get_citizen_status_data).and_return({})
      allow(operation).to receive(:get_aca_individual_evidence_data).and_return({})
      allow(operation).to receive(:tax_household_information).and_return({})
      allow(operation).to receive(:get_financial_assistance_applicant_data).and_return({})

      operation.send(:construct_family_data)

      expect(operation).to have_received(:get_basic_family_data).twice
      expect(operation).to have_received(:get_person_data).twice
    end
  end

  describe '#enrollments_for_family' do
    before do
      operation.instance_variable_set(:@family, family)
      operation.instance_variable_set(:@assistance_year, assistance_year)
    end

    context 'when family has no enrollments' do
      it 'returns empty relation' do
        result = operation.send(:enrollments_for_family)
        expect(result).to be_empty
      end
    end

    context 'when family has enrollments for assistance year' do
      let!(:enrollment) do
        FactoryBot.create(
          :hbx_enrollment,
          family: family,
          effective_on: Date.new(assistance_year, 1, 1),
          aasm_state: 'coverage_selected'
        )
      end

      it 'returns enrollments for the assistance year' do
        result = operation.send(:enrollments_for_family)
        expect(result).to include(enrollment)
      end
    end
  end

  describe '#get_basic_family_data' do
    before do
      operation.instance_variable_set(:@family, family)
    end

    context 'for primary family member' do
      let(:primary_member) { family.primary_family_member }

      it 'returns correct basic family data with is_subscriber true' do
        result = operation.send(:get_basic_family_data, primary_member)

        expect(result).to be_a(Hash)
        expect(result[:family_hbx_id]).to eq(family.hbx_assigned_id)
        expect(result[:primary_hbx_id]).to eq(family.primary_person.hbx_id)
        expect(result[:is_subscriber]).to be(true)
      end
    end

    context 'for non-primary family member' do
      it 'returns correct basic family data with is_subscriber false' do
        result = operation.send(:get_basic_family_data, family_member2)

        expect(result).to be_a(Hash)
        expect(result[:family_hbx_id]).to eq(family.hbx_assigned_id)
        expect(result[:primary_hbx_id]).to eq(family.primary_person.hbx_id)
        expect(result[:is_subscriber]).to be(false)
      end
    end
  end

  describe '#get_family_member_coverage_details' do
    let(:family_member) { family.primary_family_member }

    before do
      operation.instance_variable_set(:@family, family)
      operation.instance_variable_set(:@assistance_year, assistance_year)
    end

    context 'when member has no enrollments' do
      it 'returns empty hash' do
        enrollments = HbxEnrollment.none
        result = operation.send(:get_family_member_coverage_details, enrollments, family_member)
        expect(result).to eq({})
      end
    end

    context 'when member has health coverage' do
      let!(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product) }
      let!(:health_enrollment) do
        FactoryBot.create(
          :hbx_enrollment,
          :with_enrollment_members,
          kind: 'individual',
          family: family,
          product: product,
          enrollment_members: [family_member],
          coverage_kind: 'health',
          effective_on: Date.current.beginning_of_year,
          applied_aptc_amount: 100.0
        )
      end

      before do
        health_enrollment.hbx_enrollment_members.first.update(applicant_id: family_member.id)
      end

      it 'returns health coverage details with APTC and CSR variant' do
        enrollments = HbxEnrollment.where(id: health_enrollment.id)
        result = operation.send(:get_family_member_coverage_details, enrollments, family_member)

        expect(result).to be_a(Hash)
        expect(result.keys).to include(
          :health_cov_hbx_id,
          :health_cov_effective_on,
          :health_cov_applied_aptc,
          :health_cov_csr_variant,
          :health_cov_member_start,
          :health_cov_member_end,
          :other_health_covs
        )

        expect(result[:health_cov_hbx_id]).to eq(health_enrollment.hbx_id)
        expect(result[:health_cov_effective_on]).to eq(health_enrollment.effective_on)
        expect(result[:health_cov_applied_aptc]).to eq('100.00')
      end
    end

    context 'when member has dental coverage' do
      let!(:dental_product) { FactoryBot.create(:benefit_markets_products_dental_products_dental_product) }
      let!(:dental_enrollment) do
        FactoryBot.create(
          :hbx_enrollment,
          :with_enrollment_members,
          kind: 'individual',
          family: family,
          product: dental_product,
          enrollment_members: [family_member],
          coverage_kind: 'dental',
          effective_on: Date.current.beginning_of_year
        )
      end

      before do
        dental_enrollment.hbx_enrollment_members.first.update(applicant_id: family_member.id)
      end

      it 'returns dental coverage details without APTC or CSR variant' do
        enrollments = HbxEnrollment.where(id: dental_enrollment.id)
        result = operation.send(:get_family_member_coverage_details, enrollments, family_member)

        expect(result).to be_a(Hash)
        expect(result.keys).to include(
          :dental_cov_hbx_id,
          :dental_cov_effective_on,
          :dental_cov_member_start,
          :dental_cov_member_end,
          :other_dental_covs
        )
        expect(result.keys).not_to include(:dental_cov_applied_aptc, :dental_cov_csr_variant)

        expect(result[:dental_cov_hbx_id]).to eq(dental_enrollment.hbx_id)
        expect(result[:dental_cov_effective_on]).to eq(dental_enrollment.effective_on)
      end
    end

    context 'when member has multiple enrollments of same coverage kind' do
      let!(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product) }
      let!(:enrollment1) do
        FactoryBot.create(
          :hbx_enrollment,
          :with_enrollment_members,
          family: family,
          product: product,
          enrollment_members: [family_member],
          coverage_kind: 'health',
          hbx_id: 'enrollment_1'
        )
      end
      let!(:enrollment2) do
        FactoryBot.create(
          :hbx_enrollment,
          :with_enrollment_members,
          family: family,
          product: product,
          enrollment_members: [family_member],
          coverage_kind: 'health',
          hbx_id: 'enrollment_2'
        )
      end

      before do
        enrollment1.hbx_enrollment_members.first.update(applicant_id: family_member.id)
        enrollment2.hbx_enrollment_members.first.update(applicant_id: family_member.id)
      end

      it 'uses last enrollment as current and lists others in other_*_covs' do
        enrollments = HbxEnrollment.where(:id.in => [enrollment1.id, enrollment2.id])
        result = operation.send(:get_family_member_coverage_details, enrollments, family_member)

        expect(result[:health_cov_hbx_id]).to eq(enrollment2.hbx_id)
        expect(result[:other_health_covs]).to eq(enrollment1.hbx_id)
      end
    end
  end

  describe '#get_person_data' do
    context 'when person is provided' do
      it 'returns person data hash with all required fields' do
        result = operation.send(:get_person_data, person1)

        expect(result).to be_a(Hash)
        expect(result[:member_hbx_id]).to eq(person1.hbx_id)
        expect(result[:ssn]).to eq(person1.ssn)
        expect(result[:member_first_name]).to eq(person1.first_name)
        expect(result[:member_last_name]).to eq(person1.last_name)
      end
    end

    context 'when person is nil' do
      it 'returns empty hash' do
        result = operation.send(:get_person_data, nil)
        expect(result).to eq({})
      end
    end
  end

  describe '#get_citizen_status_data' do
    context 'when person has US citizen status' do
      before do
        allow(::ConsumerRole::US_CITIZEN_STATUS_KINDS).to receive(:include?)
          .with(person1.citizen_status).and_return(true)
      end

      it 'returns citizen_kind with status value' do
        result = operation.send(:get_citizen_status_data, person1)

        expect(result).to be_a(Hash)
        expect(result[:citizen_kind]).to eq(person1.citizen_status)
        expect(result[:immigrant_kind]).to be_nil
      end
    end

    context 'when person has immigrant status' do
      before do
        allow(::ConsumerRole::US_CITIZEN_STATUS_KINDS).to receive(:include?)
          .with(person1.citizen_status).and_return(false)
      end

      it 'returns immigrant_kind with status value' do
        result = operation.send(:get_citizen_status_data, person1)

        expect(result).to be_a(Hash)
        expect(result[:citizen_kind]).to be_nil
        expect(result[:immigrant_kind]).to eq(person1.citizen_status)
      end
    end
  end

  describe '#get_aca_individual_evidence_data' do
    let(:family_member) { family.primary_family_member }

    before do
      operation.instance_variable_set(:@family, family)
      operation.instance_variable_set(:@assistance_year, assistance_year)
    end

    context 'when family has no application' do
      it 'returns hash with nil values for all evidence types' do
        result = operation.send(:get_aca_individual_evidence_data, family_member)

        expect(result).to be_a(Hash)
        expect(result[:social_security_number_status]).to be_nil
        expect(result[:social_security_number_due_date]).to be_nil
        expect(result[:american_indian_status_status]).to be_nil
        expect(result[:american_indian_status_due_date]).to be_nil
        expect(result[:citizenship_status]).to be_nil
        expect(result[:citizenship_due_date]).to be_nil
        expect(result[:immigration_status_status]).to be_nil
        expect(result[:immigration_status_due_date]).to be_nil
      end
    end

    context 'when family has application for different year' do
      let!(:fa_application) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: assistance_year - 1,
          aasm_state: 'determined',
          submitted_at: Time.current
        )
      end

      it 'returns hash with nil values for all evidence types' do
        result = operation.send(:get_aca_individual_evidence_data, family_member)

        expect(result).to be_a(Hash)
        expect(result[:social_security_number_status]).to be_nil
        expect(result[:social_security_number_due_date]).to be_nil
        expect(result[:american_indian_status_status]).to be_nil
        expect(result[:american_indian_status_due_date]).to be_nil
        expect(result[:citizenship_status]).to be_nil
        expect(result[:citizenship_due_date]).to be_nil
        expect(result[:immigration_status_status]).to be_nil
        expect(result[:immigration_status_due_date]).to be_nil
      end
    end

    context 'when family has matching application with evidences' do
      let!(:fa_application) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: assistance_year,
          aasm_state: 'determined',
          submitted_at: Time.current
        )
      end

      let!(:fa_applicant) do
        FactoryBot.create(
          :financial_assistance_applicant,
          application: fa_application,
          family_member_id: family_member.id
        )
      end

      let!(:individual_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: fa_applicant) }

      let!(:ssn_evidence) do
        FactoryBot.create(
          :social_security_number_evidence,
          eligibility: individual_eligibility,
          key: :social_security_number,
          current_state: 'verified',
          due_on: Date.current + 30.days
        )
      end

      it 'returns evidence data with status and due dates' do
        result = operation.send(:get_aca_individual_evidence_data, family_member)

        expect(result).to be_a(Hash)
        expect(result[:social_security_number_status]).to eq(:verified)
        expect(result[:social_security_number_due_date]).to eq(Date.current + 30.days)
      end
    end
  end

  describe '#tax_household_information' do
    let(:family_member) { family.primary_family_member }

    context 'when multi_tax_household_feature is enabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?)
          .with(:temporary_configuration_enable_multi_tax_household_feature)
          .and_return(true)
      end

      context 'when no tax household group exists' do
        it 'returns empty hash' do
          result = operation.send(:tax_household_information, family_member, assistance_year)
          expect(result).to eq({})
        end
      end

      context 'when tax household group exists but no matching tax household' do
        let!(:thhg) { FactoryBot.create(:tax_household_group, family: family) }

        before do
          allow(family).to receive(:active_thhg).with(assistance_year).and_return(thhg)
        end

        it 'returns empty hash' do
          result = operation.send(:tax_household_information, family_member, assistance_year)
          expect(result).to eq({})
        end
      end

      context 'when tax household exists with aptc and csr data' do
        let!(:thhg) { FactoryBot.create(:tax_household_group, family: family) }
        let!(:thh) { FactoryBot.create(:tax_household, household: FactoryBot.create(:household, family: family), tax_household_group: thhg, max_aptc: 200.50) }
        let!(:thhm) do
          FactoryBot.create(
            :tax_household_member,
            tax_household: thh,
            applicant_id: family_member.id,
            csr_percent_as_integer: 87
          )
        end

        before do
          allow(family).to receive(:active_thhg).with(assistance_year).and_return(thhg)
        end

        it 'returns aptc and csr data' do
          result = operation.send(:tax_household_information, family_member, assistance_year)

          expect(result).to be_a(Hash)
          expect(result[:aptc_amt]).to eq(200.50)
          expect(result[:csr]).to eq(87)
        end
      end
    end

    context 'when multi_tax_household_feature is disabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?)
          .with(:temporary_configuration_enable_multi_tax_household_feature)
          .and_return(false)
      end

      context 'when no tax household exists' do
        it 'returns empty hash' do
          result = operation.send(:tax_household_information, family_member, assistance_year)
          expect(result).to eq({})
        end
      end

      context 'when tax household exists with eligibility determination' do
        let!(:household) { FactoryBot.create(:household, family: family) }
        let!(:thh) { FactoryBot.create(:tax_household, household: household) }
        let!(:eligibility_determination) do
          FactoryBot.create(:eligibility_determination, tax_household: thh, max_aptc: 150.75)
        end
        let!(:thhm) do
          FactoryBot.create(
            :tax_household_member,
            tax_household: thh,
            applicant_id: family_member.id,
            csr_percent_as_integer: 73
          )
        end

        before do
          allow(family).to receive(:active_household).and_return(household)
          allow(household).to receive(:latest_active_thh_with_year).with(assistance_year).and_return(thh)
        end

        it 'returns aptc and csr data from eligibility determination' do
          result = operation.send(:tax_household_information, family_member, assistance_year)

          expect(result).to be_a(Hash)
          expect(result[:aptc_amt]).to eq(150.75)
          expect(result[:csr]).to eq(73)
        end
      end
    end
  end

  describe '#get_finanacial_assistance_applicant_data' do
    context 'when applicant is nil' do
      it 'returns hash with nil values' do
        result = operation.send(:get_finanacial_assistance_applicant_data, nil)

        expect(result).to be_a(Hash)
        expect(result[:application_hbx_id]).to be_nil
        expect(result[:application_created_at]).to be_nil
        expect(result[:application_submitted_at]).to be_nil
        expect(result[:applicant_applying_coverage]).to be_nil
        expect(result[:cur_mth_earned_income_amt]).to be_nil
        expect(result[:cur_mth_unearned_income_amt]).to be_nil
      end
    end

    context 'when applicant has complete data' do
      let!(:fa_application) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          created_at: Date.current - 10.days,
          submitted_at: Date.current - 5.days
        )
      end

      let(:earned_income_amount) { 1000 }
      let(:unearned_income_amount) { 200 }
      let!(:fa_applicant) do
        fa_applicant = FactoryBot.create(
          :financial_assistance_applicant,
          application: fa_application,
          is_applying_coverage: true
        )
        fa_applicant.incomes << [
          FactoryBot.build(
            :financial_assistance_income,
            applicant: fa_applicant,
            amount: earned_income_amount,
            income_type: 'wages_and_salaries',
            frequency_kind: 'monthly'
          ),
          FactoryBot.build(
            :financial_assistance_income,
            applicant: fa_applicant,
            amount: unearned_income_amount,
            income_type: 'unemployment_income',
            frequency_kind: 'monthly'
          )
        ]
        fa_applicant
      end


      it 'returns complete applicant data' do
        result = operation.send(:get_finanacial_assistance_applicant_data, fa_applicant)

        expect(result).to be_a(Hash)
        expect(result[:application_hbx_id]).to eq(fa_application.hbx_id)
        expect(result[:application_created_at]).to eq(fa_application.created_at)
        expect(result[:application_submitted_at]).to eq(fa_application.submitted_at)
        expect(result[:applicant_applying_coverage]).to be(true)
        expect(result[:cur_mth_earned_income_amt]).to eq(Money.new(earned_income_amount * 100))
        expect(result[:cur_mth_unearned_income_amt]).to eq(Money.new(unearned_income_amount * 100))
      end
    end
  end

  describe '#get_financial_assistance_applicant_evidence_data' do
    context 'when applicant is nil' do
      it 'returns hash with nil values for all evidence types' do
        result = operation.send(:get_financial_assistance_applicant_evidence_data, nil)

        expect(result).to be_a(Hash)
        expect(result[:income_status]).to be_nil
        expect(result[:income_due_date]).to be_nil
        expect(result[:income_auto_extended]).to be(false)
        expect(result[:income_response]).to be_nil
        expect(result[:esi_status]).to be_nil
        expect(result[:esi_due_date]).to be_nil
        expect(result[:esi_response]).to be_nil
      end
    end

    context 'when applicant has evidence data' do
      let!(:fa_application) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id
        )
      end

      let!(:fa_applicant) do
        FactoryBot.create(
          :financial_assistance_applicant,
          application: fa_application
        )
      end

      let!(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: fa_applicant) }

      let!(:income_evidence) do
        FactoryBot.create(
          :income_evidence,
          eligibility: aptc_csr_eligibility,
          key: :income_evidence,
          current_state: 'pending',
          due_on: Date.current + 30.days,
          due_date_extended_at: Time.current
        )
      end

      let!(:esi_evidence) do
        FactoryBot.create(
          :esi_mec_evidence,
          eligibility: aptc_csr_eligibility,
          key: :esi_mec_evidence,
          current_state: 'verified',
          due_on: Date.current + 60.days
        )
      end

      before do
        allow(income_evidence).to receive(:has_determination_response?).and_return(true)
        allow(esi_evidence).to receive(:has_determination_response?).and_return(false)
      end

      it 'returns evidence data with status, due dates, and response flags' do
        result = operation.send(:get_financial_assistance_applicant_evidence_data, fa_applicant)

        expect(result).to be_a(Hash)
        expect(result[:income_status]).to eq(:pending)
        expect(result[:income_due_date]).to eq(Date.current + 30.days)
        expect(result[:income_auto_extended]).to be(true)
        expect(result[:income_response]).to be(true)
        expect(result[:esi_status]).to eq(:verified)
        expect(result[:esi_due_date]).to eq(Date.current + 60.days)
        expect(result[:esi_response]).to be(false)
      end

      it 'sets income_auto_extended only for income evidence' do
        result = operation.send(:get_financial_assistance_applicant_evidence_data, fa_applicant)

        expect(result).to have_key(:income_auto_extended)
        expect(result).not_to have_key(:esi_auto_extended)
        expect(result).not_to have_key(:non_esi_auto_extended)
        expect(result).not_to have_key(:local_mec_auto_extended)
      end
    end
  end

  describe '#get_financial_assistance_applicant_data' do
    let(:family_member) { family.primary_family_member }

    before do
      operation.instance_variable_set(:@family, family)
      operation.instance_variable_set(:@assistance_year, assistance_year)
    end

    context 'when family has no application' do
      it 'returns merged data with nil applicant data' do
        allow(operation).to receive(:get_finanacial_assistance_applicant_data).with(nil).and_return({})
        allow(operation).to receive(:get_financial_assistance_applicant_evidence_data).with(nil).and_return({})

        result = operation.send(:get_financial_assistance_applicant_data, family_member)

        expect(result).to be_a(Hash)
        expect(operation).to have_received(:get_finanacial_assistance_applicant_data).with(nil)
        expect(operation).to have_received(:get_financial_assistance_applicant_evidence_data).with(nil)
      end
    end

    context 'when family has individual market application as latest' do
      let!(:im_application) do
        FactoryBot.create(
          :individual_market_application,
          current_state: :determined,
          family: family,
          assistance_year: assistance_year,
          submitted_at: Time.current + 1.hour
        )
      end

      let!(:fa_application) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: assistance_year,
          aasm_state: 'determined',
          submitted_at: Time.current
        )
      end

      it 'returns merged data with nil applicant data' do
        allow(operation).to receive(:get_finanacial_assistance_applicant_data).with(nil).and_return({})
        allow(operation).to receive(:get_financial_assistance_applicant_evidence_data).with(nil).and_return({})

        result = operation.send(:get_financial_assistance_applicant_data, family_member)

        expect(result).to be_a(Hash)
        expect(operation).to have_received(:get_finanacial_assistance_applicant_data).with(nil)
        expect(operation).to have_received(:get_financial_assistance_applicant_evidence_data).with(nil)
      end
    end

    context 'when family has financial assistance application as latest with matching applicant' do
      let!(:fa_application) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: assistance_year,
          aasm_state: 'determined',
          submitted_at: Time.current + 1.hour
        )
      end

      let!(:fa_applicant) do
        FactoryBot.create(
          :financial_assistance_applicant,
          application: fa_application,
          family_member_id: family_member.id
        )
      end

      it 'returns merged data with applicant data' do
        applicant_data = { application_hbx_id: 'test_id' }
        evidence_data = { income_status: 'pending' }

        allow(operation).to receive(:get_finanacial_assistance_applicant_data).with(fa_applicant).and_return(applicant_data)
        allow(operation).to receive(:get_financial_assistance_applicant_evidence_data).with(fa_applicant).and_return(evidence_data)

        result = operation.send(:get_financial_assistance_applicant_data, family_member)

        expect(result).to be_a(Hash)
        expect(result).to include(applicant_data)
        expect(result).to include(evidence_data)
        expect(operation).to have_received(:get_finanacial_assistance_applicant_data).with(fa_applicant)
        expect(operation).to have_received(:get_financial_assistance_applicant_evidence_data).with(fa_applicant)
      end
    end

    context 'when no applications exist for the assistance year' do
      let!(:fa_application) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: assistance_year - 1,
          aasm_state: 'determined',
          submitted_at: Time.current
        )
      end

      it 'returns merged data with nil applicant data' do
        allow(operation).to receive(:get_finanacial_assistance_applicant_data).with(nil).and_return({})
        allow(operation).to receive(:get_financial_assistance_applicant_evidence_data).with(nil).and_return({})

        result = operation.send(:get_financial_assistance_applicant_data, family_member)

        expect(result).to be_a(Hash)
        expect(operation).to have_received(:get_finanacial_assistance_applicant_data).with(nil)
        expect(operation).to have_received(:get_financial_assistance_applicant_evidence_data).with(nil)
      end
    end
  end
end
