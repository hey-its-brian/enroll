# frozen_string_literal: true

require 'rails_helper'
require "#{FinancialAssistance::Engine.root}/spec/shared_examples/medicaid_gateway/test_case_d_response"

RSpec.describe ::FinancialAssistance::Operations::Applications::MedicaidGateway::AddEligibilityDetermination, dbclean: :after_each do
  before :all do
    DatabaseCleaner.clean
  end

  context 'when qhp_application feature is disabled' do
    before :each do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(false)
    end

    let(:application_aasm_state) { 'submitted' }
    let(:application) do
      FactoryBot.create(:financial_assistance_application, hbx_id: '200000126', aasm_state: application_aasm_state)
    end
    let!(:ed) do
      eli_d = FactoryBot.create(:financial_assistance_eligibility_determination, application: application)
      eli_d.update_attributes!(hbx_assigned_id: '12345')
      eli_d
    end
    let!(:applicant) do
      FactoryBot.create(:financial_assistance_applicant,
                        eligibility_determination_id: ed.id,
                        person_hbx_id: '95',
                        is_primary_applicant: true,
                        first_name: 'Gerald',
                        last_name: 'Rivers',
                        dob: Date.new(Date.today.year - 22, Date.today.month, Date.today.beginning_of_month.day),
                        application: application)
    end

    context 'success' do
      context 'cms_ME_simple_scenarios test_case_d' do
        include_context 'cms ME simple_scenarios test_case_d'

        before do
          @result = subject.call(response_payload)
          @application = ::FinancialAssistance::Application.by_hbx_id(response_payload[:hbx_id]).first.reload
          @ed = @application.eligibility_determinations.first
          @applicant = @ed.applicants.first
          @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(response_payload).success
        end

        it 'should return success' do
          expect(@result).to be_success
        end

        it 'returns success with the updated application' do
          expect(@result.success).to be_a(::FinancialAssistance::Application)
        end

        context 'for Application' do
          it 'should update aasm_state' do
            expect(@application.aasm_state).to eq("determined")
          end

          it 'should update determination_http_status_code' do
            expect(@application.determination_http_status_code).to eq(200)
          end

          it 'should update integrated_case_id' do
            expect(@application.integrated_case_id).to eq(@app_entity.hbx_id)
          end

          it 'should update has_eligibility_response' do
            expect(@application.has_eligibility_response).to eq(true)
          end

          it 'should update eligibility_response_payload' do
            expect(@application.eligibility_response_payload).to eq(@app_entity.to_h.to_json)
          end
        end

        context 'for Eligibility Determination' do
          it 'should update max_aptc' do
            expect(@ed.max_aptc.to_f).to eq(496.0)
          end

          it 'should update yearly_expected_contribution' do
            expect(@ed.yearly_expected_contribution.to_f).to eq(1_672.20)
          end

          it 'should update is_eligibility_determined' do
            expect(@ed.is_eligibility_determined).to eq(true)
          end

          it 'should update source' do
            expect(@ed.source).to eq('Faa')
          end

          it 'should update effective_starting_on' do
            expect(@ed.effective_starting_on).to eq(Date.today.next_month.beginning_of_month)
          end

          it 'should update determined_at' do
            expect(@ed.determined_at).to eq(Date.today)
          end

          it 'should update aptc_csr_annual_household_income' do
            expect(@ed.aptc_csr_annual_household_income.to_f).to eq(16_000.0)
          end

          it 'should update csr_annual_income_limit' do
            expect(@ed.csr_annual_income_limit.to_f).to eq(142_912_000.0)
          end
        end

        context 'for Applicant' do
          it 'should update is_ia_eligible' do
            expect(@applicant.is_ia_eligible).to eq(true)
          end

          it 'is expected to update is_csr_eligible' do
            expect(@applicant.is_csr_eligible).to eq(true)
          end

          it 'should update is_medicaid_chip_eligible' do
            expect(@applicant.is_medicaid_chip_eligible).to eq(false)
          end

          it 'should update is_non_magi_medicaid_eligible' do
            expect(@applicant.is_non_magi_medicaid_eligible).to eq(false)
          end

          it 'should update is_eligible_for_non_magi_reasons' do
            expect(@applicant.is_eligible_for_non_magi_reasons).to eq(true)
          end

          it 'should update medicaid_household_size & not to be nil' do
            expect(@applicant.medicaid_household_size).not_to be_nil
            expect(@applicant.medicaid_household_size).to eq(0)
          end

          it 'should update magi_medicaid_category' do
            expect(@applicant.magi_medicaid_category).not_to be_nil
            expect(@applicant.magi_medicaid_category).to eq('none')
          end

          it 'should update csr_percent_as_integer value' do
            expect(@applicant.csr_percent_as_integer).to eq(-1)
          end

          it 'should update csr_percent_as_integer value' do
            expect(@applicant.csr_eligibility_kind).to eq("csr_limited")
          end

          it 'should update is_gap_filling' do
            expect(@applicant.is_gap_filling).to eq(true)
          end

          context 'member_determinations' do
            before do
              ped = response_payload[:tax_households].first[:tax_household_members].first[:product_eligibility_determination]
              @payload_member_determinations = ped[:member_determinations]
            end

            it 'should create a single member_determination for each kind' do
              @payload_member_determinations.each do |payload_member_determination|
                member_determination = @applicant.member_determinations.select { |md| md.kind == payload_member_determination[:kind] }
                expect(member_determination.count).to eq(1)
              end
            end

            it 'should update member_determination value' do
              @payload_member_determinations.each do |payload_member_determination|
                member_determination = @applicant.member_determinations.detect { |md| md.kind == payload_member_determination[:kind] }
                expect(member_determination.criteria_met).to eq(payload_member_determination[:criteria_met])
                expect(member_determination.determination_reasons).to eq(payload_member_determination[:determination_reasons])
                expect(member_determination.eligibility_overrides).to eq(payload_member_determination[:eligibility_overrides])
              end
            end
          end
        end
      end
    end

    context 'failure' do
      context 'invalid response payload' do
        before do
          @result = subject.call({ test: 'test' })
        end

        it 'should return failure' do
          expect(@result).to be_failure
        end
      end

      context 'no matching persistence application' do
        include_context 'cms ME simple_scenarios test_case_d'

        before do
          response_payload.merge!({ hbx_id: '999999' })
          @result = subject.call(response_payload)
        end

        it 'should return failure' do
          expect(@result).to be_failure
        end

        it 'should return failure with error message' do
          expect(@result.failure).to eq('Found 0 applications with given hbx_id: 999999')
        end
      end
    end
  end

  context 'when qhp_application feature is enabled' do
    before :each do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
    end

    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:person) { FactoryBot.create(:person, ssn: ssn, age_off_excluded: true, dob: Date.new(Date.today.year - 22, Date.today.month, Date.today.beginning_of_month.day)) }
    let(:application) do
      FactoryBot.create(:financial_assistance_application, hbx_id: '200000126', aasm_state: "submitted", family_id: family.id)
    end

    let(:ed) do
      eli_d = FactoryBot.create(:financial_assistance_eligibility_determination, application: application)
      eli_d.update_attributes!(hbx_assigned_id: '12345')
      eli_d
    end

    let(:applicant) do
      FactoryBot.create(:financial_assistance_applicant,
                        eligibility_determination_id: ed.id,
                        person_hbx_id: '95',
                        is_primary_applicant: true,
                        first_name: person.first_name,
                        last_name: person.last_name,
                        encrypted_ssn: person.encrypted_ssn,
                        dob: Date.new(Date.today.year - 22, Date.today.month, Date.today.beginning_of_month.day),
                        application: application)
    end

    let(:aptc_csr)  do
      eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: applicant)
      old_state = FactoryBot.build(:v3_state_history, created_at: 2.days.ago)
      new_state = FactoryBot.build(:v3_state_history, created_at: 1.day.ago)
      eligibility.state_histories << old_state
      eligibility.state_histories << new_state
      eligibility.save!
      eligibility
    end

    let(:individual_market)  do
      eligibility = FactoryBot.create(:individual_market_eligibility, eligible: applicant)
      old_state = FactoryBot.build(:v3_state_history, created_at: 2.days.ago)
      new_state = FactoryBot.build(:v3_state_history, created_at: 1.day.ago)
      eligibility.state_histories << old_state
      eligibility.state_histories << new_state
      eligibility.save!
      eligibility
    end

    let(:evidence) do
      FactoryBot.create(:income_evidence, eligibility: aptc_csr, _type: 'FinancialAssistance::Evidences::IncomeEvidence',key: :income_evidence, title: 'Income Evidence', determined_at: TimeKeeper.date_of_record,
                                          description: 'Income Evidence Description', current_state: :pending)
    end
    let(:old_state_history) { FactoryBot.create(:v3_state_history, status_trackable: evidence, from_state: :initial, to_state: :pending, created_at: 2.days.ago) }

    let(:hbx_profile) {FactoryBot.create(:hbx_profile)}
    let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
    let(:benefit_coverage_period) { hbx_profile.benefit_sponsorship.benefit_coverage_periods.first }
    context 'success' do
      let(:ssn) { '123456789' }
      context 'applicant in valid' do
        include_context 'cms ME simple_scenarios test_case_d'

        before do
          individual_market
          old_state_history
          allow(subject).to receive(:all_hub_calls_turned_off?).and_return(false)
          allow(HbxProfile).to receive(:current_hbx).and_return hbx_profile
          allow(hbx_profile).to receive(:benefit_sponsorship).and_return benefit_sponsorship
          allow(benefit_sponsorship).to receive(:current_benefit_period).and_return(benefit_coverage_period)
          @result = subject.call(response_payload)
          updated_application = ::FinancialAssistance::Application.by_hbx_id(response_payload[:hbx_id]).first
          updated_applicant = updated_application.applicants.first
          @aptc_csr_eligibility = updated_applicant.aptc_csr_eligibility
        end

        it 'should return success' do
          expect(@result).to be_success
        end

        it 'should return success with a message' do
          expect(@aptc_csr_eligibility).not_to be_nil
          expect(@aptc_csr_eligibility.state_histories.count).to eq(3)
          expect(@aptc_csr_eligibility.income_evidence).not_to be_nil
          expect(@aptc_csr_eligibility.income_evidence.current_state).to eq(:pending)
          expect(@aptc_csr_eligibility.income_evidence.state_histories.count).to eq(1)
          expect(@aptc_csr_eligibility.income_evidence.verification_histories.count).to eq(1)
        end
      end

      context 'with existing aptc enrollment' do
        include_context 'cms ME simple_scenarios test_case_d'
        let(:rating_area) { FactoryBot.create_default(:benefit_markets_locations_rating_area) }
        let(:product) {FactoryBot.create(:benefit_markets_products_health_products_health_product, :ivl_product)}
        let(:consumer_role) { FactoryBot.create(:consumer_role, person: person, is_active: true) }

        let(:existing_aptc_enrollment) do
          FactoryBot.create(
            :hbx_enrollment,
            :individual_aptc,
            :with_silver_health_product,
            family: family,
            household: family.active_household,
            coverage_kind: 'health',
            consumer_role: consumer_role,
            effective_on: Date.new(application.assistance_year, 1, 1),
            rating_area_id: rating_area.id,
            aasm_state: 'coverage_selected'
          )
        end

        before do
          individual_market
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:apply_aggregate_to_enrollment).and_return(true)
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:temporary_configuration_enable_multi_tax_household_feature).and_return(true)
          allow(EnrollRegistry[:fifteenth_of_the_month_rule_overridden].feature).to receive(:is_enabled).and_return(true)
          allow(HbxProfile).to receive(:current_hbx).and_return hbx_profile
          allow(hbx_profile).to receive(:benefit_sponsorship).and_return benefit_sponsorship
          allow(benefit_sponsorship).to receive(:current_benefit_period).and_return(benefit_coverage_period)
          allow(benefit_coverage_period).to receive(:slcsp_id).and_return(product.id)
          allow(::Operations::Products::ProductOfferedInServiceArea).to receive(:new).and_return(double(call: double(:success? => true)))
          existing_aptc_enrollment
          family
          @result = subject.call(response_payload)
        end

        let(:new_effective_date) { Insured::Factories::SelfServiceFactory.new_enrollment_effective_on_date(existing_aptc_enrollment, nil) }

        it 'should create a new aptc enrollment' do
          # if the existing enrollment was created after December 1,
          # it will have a next year effective date and no new enrollments will generate
          if new_effective_date.year == existing_aptc_enrollment.effective_on.year
            expect(family.active_household.hbx_enrollments.count).to eq(2)
          else
            expect(family.active_household.hbx_enrollments.count).to eq(1)
          end
        end

        it "terminates the existing aptc enrollment if the new effective date year matches enrollment effective on year" do
          if new_effective_date.year == existing_aptc_enrollment.effective_on.year
            existing_aptc_enrollment.reload
            expect(existing_aptc_enrollment.aasm_state).to eq('coverage_terminated')
          end
        end
      end
    end

    context 'failure' do
      let(:ssn) { nil }
      context 'when applicant is invalid' do
        include_context 'cms ME simple_scenarios test_case_d'

        before do
          individual_market
          old_state_history
          allow(subject).to receive(:all_hub_calls_turned_off?).and_return(false)
          allow(HbxProfile).to receive(:current_hbx).and_return hbx_profile
          allow(hbx_profile).to receive(:benefit_sponsorship).and_return benefit_sponsorship
          allow(benefit_sponsorship).to receive(:current_benefit_period).and_return(benefit_coverage_period)
          @result = subject.call(response_payload)
          updated_application = ::FinancialAssistance::Application.by_hbx_id(response_payload[:hbx_id]).first
          updated_applicant = updated_application.applicants.first
          @aptc_csr_eligibility = updated_applicant.aptc_csr_eligibility
        end

        it 'should return success' do
          expect(@result).to be_success
        end

        it 'should not publish the hub event,
            record the failure,
            proceed with completing the determination' do
          expect(@aptc_csr_eligibility).not_to be_nil
          expect(@aptc_csr_eligibility.state_histories.count).to eq(3)
          expect(@aptc_csr_eligibility.income_evidence).not_to be_nil
          expect(@aptc_csr_eligibility.income_evidence.current_state).to eq(:negative_response_received)
          expect(@aptc_csr_eligibility.income_evidence.state_histories.count).to eq(2)
          expect(@aptc_csr_eligibility.income_evidence.verification_histories.count).to eq(2)
        end
      end
    end
  end
end
