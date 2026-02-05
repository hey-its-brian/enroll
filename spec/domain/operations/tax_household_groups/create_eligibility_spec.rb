# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::TaxHouseholdGroups::CreateEligibility, dbclean: :after_each do

  it 'should be a container-ready operation' do
    expect(subject.respond_to?(:call)).to be_truthy
  end

  describe 'invalid params' do

    let(:params) do
      {}
    end

    it 'should return failure' do
      result = subject.call(params)
      expect(result.failure?).to eq true
    end
  end

  describe 'valid params' do
    let(:params) do
      { family: family, th_group_info: tax_household_group.deep_symbolize_keys! }
    end

    let(:family) do
      family = FactoryBot.build(:family, person: primary)
      family.family_members = [
        FactoryBot.build(:family_member, is_primary_applicant: true, is_active: true, family: family, person: primary),
        FactoryBot.build(:family_member, is_primary_applicant: false, is_active: true, family: family, person: dependent1),
        FactoryBot.build(:family_member, is_primary_applicant: false, is_active: true, family: family, person: dependent2)
      ]

      family.person.person_relationships.push PersonRelationship.new(relative_id: dependent1.id, kind: 'spouse')
      family.person.person_relationships.push PersonRelationship.new(relative_id: dependent2.id, kind: 'child')
      family.save
      family
    end

    let(:primary_fm) { family.primary_applicant }
    let(:dependents) { family.dependents }

    let(:primary) { FactoryBot.create(:person, :with_consumer_role) }
    let(:dependent1) { FactoryBot.create(:person, :with_consumer_role) }
    let(:dependent2) { FactoryBot.create(:person, :with_consumer_role) }

    let(:tax_household_group) do
      {
        "person_id" => primary.id.to_s,
        "family_actions_id" => "family_actions_#{family.id}",
        "effective_date" => TimeKeeper.date_of_record.to_s,
        "tax_households" => {
          "0" => {
            "members" => [
              {
                "pdc_type" => "is_ia_eligible",
                "csr" => "100",
                "is_filer" => "on",
                "member_name" => "Ivl ivl",
                "family_member_id" => primary_fm.id.to_s
              },
              {
                "pdc_type" => "is_ia_eligible",
                "csr" => "87",
                "is_filer" => nil,
                "member_name" => "Spouse spouse",
                "family_member_id" => dependents[0].id.to_s
              }
            ].to_json,
            "monthly_expected_contribution" => "400"
          },
          "1" => {
            "members" => [
              {
                "pdc_type" => "is_ia_eligible",
                "csr" => "94",
                "is_filer" => "on",
                "member_name" => "Child child",
                "family_member_id" => dependents[1].id.to_s
              }
            ].to_json,
            "monthly_expected_contribution" => "300"
          }
        }
      }
    end

    it 'should create grants' do
      subject.call(params)
      eligibility_determination = family.reload.eligibility_determination

      expect(eligibility_determination.grants.size).to eq 2
    end

    context 'when there is a current year health enrollment' do
      let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, :silver, benefit_market_kind: :aca_individual, kind: :health) }
      let!(:hbx_enrollment) do
        FactoryBot.create(:hbx_enrollment,
                          :with_enrollment_members,
                          :coverage_selected,
                          consumer_role_id: primary.consumer_role.id,
                          product: product,
                          kind: 'individual',
                          coverage_kind: 'health',
                          family: family,
                          effective_on: Date.new(Date.today.year, 1, 1),
                          aasm_state: 'coverage_selected')
      end

      let(:new_effective_date) { Insured::Factories::SelfServiceFactory.new_enrollment_effective_on_date(hbx_enrollment, nil) }

      context 'when apply_aggregate_to_enrollment flag is enabled' do
        before do
          allow(EnrollRegistry[:apply_aggregate_to_enrollment].feature).to receive(:is_enabled).and_return(true)
          allow(EnrollRegistry[:qhp_application].feature).to receive(:is_enabled).and_return(false)
          allow(EnrollRegistry[:temporary_configuration_enable_multi_tax_household_feature].feature).to receive(:is_enabled).and_return(true)
          allow(::Insured::Factories::SelfServiceFactory).to receive(:mthh_update_enrollment_for_aptcs).and_return(nil)
          allow(EnrollRegistry[:fifteenth_of_the_month_rule_overridden].feature).to receive(:is_enabled).and_return(true)
        end

        it 'should call OnNewDetermination :eligibility_creation generation reason' do
          # if the existing enrollment was created after December 1,
          # it will have a next year effective date and no new enrollments will generate
          if new_effective_date.year == hbx_enrollment.effective_on.year
            subject.call(params)
            new_enrollments = family.reload.hbx_enrollments.where(generation_reason: :eligibility_creation)
            expect(new_enrollments).to_not be_empty
          end
        end
      end
    end

    context 'when there is an application' do
      let(:application) { FactoryBot.create(:financial_assistance_application, :with_applicants, family: family, aasm_state: 'determined', effective_date: Date.new(Date.today.year, 1, 1)) }
      let(:applicant) { application.applicants.first }

      before do
        applicant.build_aptc_eligibilities_evidences
        applicant.save
        params[:updated_by] = 'admin@example.com'
        allow(family).to receive(:latest_application).and_return(application)
      end

      it 'Should verification history on evidences' do
        subject.call(params)
        expect(applicant.aptc_csr_eligibility.evidences.first.verification_histories.size).to eq 1
        expect(applicant.aptc_csr_eligibility.evidences.first.verification_histories.first.action).to eq 'Manually created new eligibility'
        expect(applicant.aptc_csr_eligibility.evidences.first.verification_histories.first.updated_by).to eq 'admin@example.com'
      end
    end
  end

  describe '#call' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }

    let(:spouse_person) do
      per = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
      person.ensure_relationship_with(per, 'spouse')
      per
    end

    let(:child_person) do
      per = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
      person.ensure_relationship_with(per, 'child')
      per
    end

    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:spouse_member) { FactoryBot.create(:family_member, family: family, person: spouse_person, is_active: spouse_member_active) }
    let(:child_member) { FactoryBot.create(:family_member, family: family, person: child_person) }

    let(:params) do
      { family: spouse_member.family, th_group_info: {} }
    end

    context 'with:
      - none of the active family members are applying for coverage
      - spouse_member is applying for coverage but is a destroyed member(not an active family member)
    ' do

      let(:spouse_member_active) { false }

      before do
        child_member.person.consumer_role.update_attributes(is_applying_coverage: false)
        person.consumer_role.update_attributes(is_applying_coverage: false)
      end

      it 'returns a failure monad' do
        expect(subject.call(params).failure).to eq(l10n('create_eligibility_tool.no_members_applying_coverage'))
      end
    end

    [
      {
        pdc_type: 'is_ia_eligible',
        csr: '87',
        expected: {
          is_ia_eligible: true,
          is_uqhp_eligible: false,
          is_medicaid_chip_eligible: false,
          is_without_assistance: false,
          is_totally_ineligible: false,
          csr_percent_as_integer: 87
        }
      },
      {
        pdc_type: 'is_uqhp_eligible',
        csr: '0',
        expected: {
          is_ia_eligible: false,
          is_uqhp_eligible: true,
          is_medicaid_chip_eligible: false,
          is_without_assistance: true,
          is_totally_ineligible: false,
          csr_percent_as_integer: 0
        }
      },
      {
        pdc_type: 'is_medicaid_chip_eligible',
        csr: '0',
        expected: {
          is_ia_eligible: false,
          is_uqhp_eligible: false,
          is_medicaid_chip_eligible: true,
          is_without_assistance: false,
          is_totally_ineligible: false,
          csr_percent_as_integer: 0
        }
      },
      {
        pdc_type: 'is_totally_ineligible',
        csr: '0',
        expected: {
          is_ia_eligible: false,
          is_uqhp_eligible: false,
          is_medicaid_chip_eligible: false,
          is_without_assistance: false,
          is_totally_ineligible: true,
          csr_percent_as_integer: 0
        }
      }
    ].each do |test_case|
      context "when pdc_type is #{test_case[:pdc_type]}" do
        let(:th_group_info) do
          {
            "effective_date" => TimeKeeper.date_of_record.strftime('%m/%d/%Y'),
            "tax_households" => {
              "0" => {
                "members" => [{
                  "pdc_type" => test_case[:pdc_type],
                  "csr" => test_case[:csr],
                  "family_member_id" => family.primary_applicant.id.to_s,
                  "is_filer" => "on"
                }].to_json,
                "monthly_expected_contribution" => "400"
              }
            }
          }.deep_symbolize_keys!
        end

        let(:params) { { family: family, th_group_info: th_group_info } }

        it 'sets correct eligibility flags on tax household member' do
          subject.call(params)
          th_member = family.reload.tax_household_groups.last
                            .tax_households.first
                            .tax_household_members.first

          test_case[:expected].each do |attr, expected_value|
            expect(th_member.send(attr)).to eq(expected_value),
                                            "Expected #{attr} to be #{expected_value} for pdc_type: #{test_case[:pdc_type]}"
          end
        end
      end
    end
  end
end
