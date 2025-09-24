# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::HbxEnrollments::UpdateApplicationEvidences, :type => :model, dbclean: :around_each do
  context 'when FA application is in context' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role)}
    let(:dependent) { FactoryBot.create(:person, :with_consumer_role)}
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person)}
    let(:dependent_member) { FactoryBot.create(:family_member, family: family, person: dependent) }
    let(:address) { family.primary_person.rating_address }
    let(:effective_date) { TimeKeeper.date_of_record.beginning_of_year }
    let(:application_period) { effective_date.beginning_of_year..effective_date.end_of_year }
    let(:rating_area) do
      ::BenefitMarkets::Locations::RatingArea.rating_area_for(address, during: effective_date) || FactoryBot.create_default(:benefit_markets_locations_rating_area, active_year: effective_date.year)
    end
    let(:service_area) do
      ::BenefitMarkets::Locations::ServiceArea.service_areas_for(address, during: effective_date).first || FactoryBot.create_default(:benefit_markets_locations_service_area, active_year: effective_date.year)
    end

    let(:product) do
      prod =
        FactoryBot.create(
          :benefit_markets_products_health_products_health_product,
          :with_issuer_profile,
          :silver,
          benefit_market_kind: :aca_individual,
          kind: :health,
          application_period: application_period,
          service_area: service_area,
          csr_variant_id: '01'
        )
      prod.premium_tables = [premium_table]
      prod.save
      prod
    end

    let(:premium_table)  { build(:benefit_markets_products_premium_table, effective_period: application_period, rating_area: rating_area) }

    let(:enrollment) do
      en = FactoryBot.create(
        :hbx_enrollment,
        :with_enrollment_members,
        :individual_assisted,
        family: family,
        applied_aptc_amount: applied_aptc_amount,
        consumer_role_id: person.consumer_role.id,
        enrollment_members: [family.family_members.first],
        product: product
      )

      en.workflow_state_transitions << FactoryBot.build(:workflow_state_transition, to_state: 'coverage_selected', from_state: 'shopping', event: 'select_coverage')
      en.save!
      en
    end

    let(:tax_household) do
      current_tax_household_group.tax_households.first
    end

    let(:thhm_enrollment_members) do
      enrollment.hbx_enrollment_members.collect do |member|
        FactoryBot.build(:tax_household_member_enrollment_member, hbx_enrollment_member_id: member.id, family_member_id: member.applicant_id, tax_household_member_id: "123")
      end
    end

    let(:thhe) do
      tax_household_enrollment = FactoryBot.build(:tax_household_enrollment, enrollment_id: enrollment.id, tax_household_id: tax_household.id,
                                                                             health_product_hios_id: enrollment.product.hios_id,
                                                                             dental_product_hios_id: nil, tax_household_members_enrollment_members: thhm_enrollment_members)
      tax_household_enrollment.save
      tax_household_enrollment
    end

    let(:application) do
      FactoryBot.create(:financial_assistance_application,
                        family_id: BSON::ObjectId.new,
                        aasm_state: 'draft',
                        assistance_year: TimeKeeper.date_of_record.year,
                        effective_date: Date.today)
    end

    let(:applicant) do
      FactoryBot.create(:financial_assistance_applicant,
                        application: application,
                        dob: Date.today - 38.years,
                        is_primary_applicant: false,
                        family_member_id: family.family_members.first.id)
    end

    let(:aptc_csr_eligibility)  do
      eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: applicant)
      old_state = FactoryBot.build(:v3_state_history, created_at: 2.days.ago)
      new_state = FactoryBot.build(:v3_state_history, created_at: 1.day.ago)
      eligibility.state_histories << old_state
      eligibility.state_histories << new_state
      eligibility.save!
      eligibility
    end

    let(:create_aptc_csr_evidences) do
      FactoryBot.create(:income_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::IncomeEvidence', key: :income_evidence, current_state: 'pending')
      FactoryBot.create(:esi_mec_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::EsiMecEvidence', key: :esi_mec_evidence, title: 'Esi MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                           description: 'EsiMecEvidence', current_state: "verified")
      FactoryBot.create(:non_esi_mec_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::NonEsiMecEvidence', key: :non_esi_mec_evidence, title: 'Non Esi MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                               description: 'NonEsiMecEvidence', current_state: "negative_response_received", verification_outstanding: false, is_satisfied: true)
      FactoryBot.create(:local_mec_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::LocalMecEvidence', key: :local_mec_evidence, title: 'Local MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                             description: 'LocalMecEvidence', current_state: "outstanding", due_on: nil)
    end

    let(:create_individual_market_evidences) do
      ivl_eligibility = FactoryBot.create(:individual_market_eligibility, eligible: applicant)
      FactoryBot.create(:alive_evidence, :pending, eligibility: ivl_eligibility)
      FactoryBot.create(:american_indian_evidence, :verified, eligibility: ivl_eligibility)
      FactoryBot.create(:citizenship_evidence, :rejected, eligibility: ivl_eligibility, due_on: Date.today + 5.days, verification_outstanding: true, is_satisfied: false)
      FactoryBot.create(:social_security_number_evidence, :pending, eligibility: ivl_eligibility)
    end

    let(:current_tax_household_group) do
      FactoryBot.create(:tax_household_group, :active_current_year, family: family, tax_households: [
        FactoryBot.build(:tax_household, household: family.active_household)
      ])
    end

    before do
      create_aptc_csr_evidences
      create_individual_market_evidences
      current_tax_household_group.set(application_gid: application.to_global_id.to_s)

    end

    context "when enrolled" do
      context "when aptc is applied on enrolment member" do
        let(:applied_aptc_amount) { Money.new(44_500) }

        before do
          enrollment
          thhe
          ::Operations::HbxEnrollments::UpdateApplicationEvidences.new.call({gid: enrollment.to_global_id.to_s})
          applicant.reload
          @aptc_csr_eligibility = applicant.aptc_csr_eligibility
          @individual_market_eligibility = applicant.individual_market_eligibility
        end

        context "for aptc_csr_eligibility evidences" do
          it "should move income_evidence to outstanding state" do
            income_evidence = @aptc_csr_eligibility.income_evidence
            expect(income_evidence).to be_outstanding
            expect(income_evidence.due_on).to eq income_evidence.schedule_verification_due_on
            expect(income_evidence.verification_outstanding).to be_truthy
            expect(income_evidence.is_satisfied).to be_falsey
            expect(income_evidence.state_histories.last.from_state).to eq :pending
            expect(income_evidence.state_histories.last.to_state).to eq :outstanding
          end

          it "should not move esi_mec_evidence to outstanding state" do
            esi_mec_evidence = @aptc_csr_eligibility.esi_mec_evidence
            expect(esi_mec_evidence).not_to be_outstanding
            expect(esi_mec_evidence.current_state).to eq :verified
          end

          it "should move non_esi_mec_evidence to outstanding state" do
            non_esi_mec_evidence = @aptc_csr_eligibility.non_esi_mec_evidence
            expect(non_esi_mec_evidence).to be_outstanding
            expect(non_esi_mec_evidence.due_on).to eq non_esi_mec_evidence.schedule_verification_due_on
            expect(non_esi_mec_evidence.verification_outstanding).to be_truthy
            expect(non_esi_mec_evidence.is_satisfied).to be_falsey
            expect(non_esi_mec_evidence.state_histories.last.from_state).to eq :negative_response_received
            expect(non_esi_mec_evidence.state_histories.last.to_state).to eq :outstanding
          end

          it "should not update local mec evidence if it is in outstanding" do
            local_mec_evidence = @aptc_csr_eligibility.local_mec_evidence
            expect(local_mec_evidence).to be_outstanding
            expect(local_mec_evidence.state_histories.present?).to be_falsey
          end
        end

        context "for individual market eligibility" do
          it "should not move citizenship evidence from rejected" do
            citizenship_evidence = @individual_market_eligibility.citizenship_evidence
            expect(citizenship_evidence).to be_rejected
            expect(citizenship_evidence.due_on).to eq(Date.today + 5.days)
            expect(citizenship_evidence.verification_outstanding).to be_truthy
            expect(citizenship_evidence.is_satisfied).to be_falsey
          end

          it "should move social security evidence to outstanding state" do
            social_security_evidence = @individual_market_eligibility.social_security_number_evidence
            expect(social_security_evidence).to be_outstanding
            expect(social_security_evidence.due_on).to eq social_security_evidence.schedule_verification_due_on
            expect(social_security_evidence.verification_outstanding).to be_truthy
            expect(social_security_evidence.is_satisfied).to be_falsey
            expect(social_security_evidence.state_histories.last.from_state).to eq :pending
            expect(social_security_evidence.state_histories.last.to_state).to eq :outstanding
          end
        end
      end

      context "when aptc is not applied on enrolment member" do
        let(:applied_aptc_amount) { Money.new(0) }

        before do
          enrollment
          thhe
          ::Operations::HbxEnrollments::UpdateApplicationEvidences.new.call({gid: enrollment.to_global_id.to_s})
          applicant.reload
          @aptc_csr_eligibility = applicant.aptc_csr_eligibility
          @individual_market_eligibility = applicant.individual_market_eligibility
        end

        context "for aptc_csr_eligibility evidences" do
          it "should move eligibility to verification_in_progress" do
            expect(@aptc_csr_eligibility).to be_verification_in_progress
            expect(@aptc_csr_eligibility.state_histories.last.from_state).to eq :initial
            expect(@aptc_csr_eligibility.state_histories.last.to_state).to eq :verification_in_progress
          end

          it "should not change income_evidence state" do
            income_evidence = @aptc_csr_eligibility.income_evidence
            expect(income_evidence).to be_pending
            expect(income_evidence.state_histories.present?).to be_falsey
          end

          it "should not change esi_mec_evidence state" do
            esi_mec_evidence = @aptc_csr_eligibility.esi_mec_evidence
            expect(esi_mec_evidence).to be_verified
            expect(esi_mec_evidence.state_histories.present?).to be_falsey
          end

          it "should not change non_esi_mec_evidence state" do
            non_esi_mec_evidence = @aptc_csr_eligibility.non_esi_mec_evidence
            expect(non_esi_mec_evidence).to be_negative_response_received
            expect(non_esi_mec_evidence.state_histories.present?).to be_falsey
          end

          it "should update local mec evidence to negative_response_received" do
            local_mec_evidence = @aptc_csr_eligibility.local_mec_evidence
            expect(local_mec_evidence).to be_negative_response_received
            expect(local_mec_evidence.state_histories.present?).to be_truthy
            expect(local_mec_evidence.state_histories.last.from_state).to eq :outstanding
            expect(local_mec_evidence.state_histories.last.to_state).to eq :negative_response_received
          end
        end

        context "for individual market eligibility" do
          it "should move eligibility to verification_in_progress" do
            expect(@individual_market_eligibility).to be_verification_in_progress
            expect(@individual_market_eligibility.state_histories.last.from_state).to eq :initial
            expect(@individual_market_eligibility.state_histories.last.to_state).to eq :verification_in_progress
          end

          it "should move alive evidence to outstanding state" do
            alive_evidence = @individual_market_eligibility.alive_evidence
            expect(alive_evidence).to be_outstanding
            expect(alive_evidence.due_on).to eq alive_evidence.schedule_verification_due_on
            expect(alive_evidence.verification_outstanding).to be_truthy
            expect(alive_evidence.is_satisfied).to be_falsey
            expect(alive_evidence.state_histories.last.from_state).to eq :pending
            expect(alive_evidence.state_histories.last.to_state).to eq :outstanding
          end

          it "should not move citizenship evidence from rejected" do
            citizenship_evidence = @individual_market_eligibility.citizenship_evidence
            expect(citizenship_evidence).to be_rejected
            expect(citizenship_evidence.due_on).to eq(Date.today + 5.days)
            expect(citizenship_evidence.verification_outstanding).to be_truthy
            expect(citizenship_evidence.is_satisfied).to be_falsey
          end

          it "should move social security evidence to outstanding state" do
            social_security_evidence = @individual_market_eligibility.social_security_number_evidence
            expect(social_security_evidence).to be_outstanding
            expect(social_security_evidence.due_on).to eq social_security_evidence.schedule_verification_due_on
            expect(social_security_evidence.verification_outstanding).to be_truthy
            expect(social_security_evidence.is_satisfied).to be_falsey
            expect(social_security_evidence.state_histories.last.from_state).to eq :pending
            expect(social_security_evidence.state_histories.last.to_state).to eq :outstanding
          end
        end
      end
    end

    context "when one of the member is not enrolled" do
      before do
        enrollment
        thhe
      end

      let(:dependent_applicant) do
        FactoryBot.create(:financial_assistance_applicant,
                          application: application,
                          dob: Date.today - 38.years,
                          is_primary_applicant: false,
                          family_member_id: dependent_member.id)
      end

      let(:dependent_aptc_csr_eligibility)  do
        eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: dependent_applicant)
        old_state = FactoryBot.build(:v3_state_history, created_at: 2.days.ago)
        new_state = FactoryBot.build(:v3_state_history, created_at: 1.day.ago)
        eligibility.state_histories << old_state
        eligibility.state_histories << new_state
        eligibility.save!
        eligibility
      end

      let(:create_dependent_aptc_csr_evidences) do
        FactoryBot.create(:income_evidence, eligibility: dependent_aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::IncomeEvidence',
                                            key: :income_evidence, current_state: 'pending')
        FactoryBot.create(:esi_mec_evidence, eligibility: dependent_aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::EsiMecEvidence',
                                             key: :esi_mec_evidence, title: 'Esi MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                             description: 'EsiMecEvidence', current_state: "verified")
        FactoryBot.create(:non_esi_mec_evidence, eligibility: dependent_aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::NonEsiMecEvidence',
                                                 key: :non_esi_mec_evidence, title: 'Non Esi MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                                 description: 'NonEsiMecEvidence', current_state: "negative_response_received",  due_on: nil, verification_outstanding: false, is_satisfied: true)
        FactoryBot.create(:local_mec_evidence, eligibility: dependent_aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::LocalMecEvidence',
                                               key: :local_mec_evidence, title: 'Local MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                               description: 'LocalMecEvidence', current_state: "outstanding", verification_outstanding: true, is_satisfied: false, due_on: Date.today + 5.days)
      end

      let(:create_dependent_individual_market_evidences) do
        ivl_eligibility = FactoryBot.create(:individual_market_eligibility, eligible: dependent_applicant)
        FactoryBot.create(:alive_evidence, :pending, eligibility: ivl_eligibility)
        FactoryBot.create(:american_indian_evidence, :outstanding, eligibility: ivl_eligibility)
        FactoryBot.create(:citizenship_evidence, :rejected, eligibility: ivl_eligibility, due_on: Date.today + 5.days, verification_outstanding: true, is_satisfied: false)
        FactoryBot.create(:social_security_number_evidence, :pending, eligibility: ivl_eligibility, verification_outstanding: false, is_satisfied: true)
      end

      context "when aptc is applied on enrolment member" do
        let(:applied_aptc_amount) { Money.new(400) }

        before do
          enrollment
          create_dependent_aptc_csr_evidences
          create_dependent_individual_market_evidences
          ::Operations::HbxEnrollments::UpdateApplicationEvidences.new.call({gid: enrollment.to_global_id.to_s})
          applicant.reload
          dependent_applicant.reload
          @primary_aptc_csr_eligibility = applicant.aptc_csr_eligibility
          @primary_individual_market_eligibility = applicant.individual_market_eligibility
          @dependent_aptc_csr_eligibility = dependent_applicant.aptc_csr_eligibility
          @dependent_individual_market_eligibility = dependent_applicant.individual_market_eligibility
        end

        context "for aptc_csr_eligibility evidences" do
          it "should move primary income_evidence to outstanding state" do
            income_evidence = @primary_aptc_csr_eligibility.income_evidence
            expect(income_evidence).to be_outstanding
            expect(income_evidence.due_on).to eq income_evidence.schedule_verification_due_on
            expect(income_evidence.verification_outstanding).to be_truthy
            expect(income_evidence.is_satisfied).to be_falsey
            expect(income_evidence.state_histories.last.from_state).to eq :pending
            expect(income_evidence.state_histories.last.to_state).to eq :outstanding
          end

          it "should not move primary esi_mec_evidence to outstanding state" do
            esi_mec_evidence = @primary_aptc_csr_eligibility.esi_mec_evidence
            expect(esi_mec_evidence).not_to be_outstanding
            expect(esi_mec_evidence.current_state).to eq :verified
          end

          it "should move primary non_esi_mec_evidence to outstanding state" do
            non_esi_mec_evidence = @primary_aptc_csr_eligibility.non_esi_mec_evidence
            expect(non_esi_mec_evidence).to be_outstanding
            expect(non_esi_mec_evidence.due_on).to eq non_esi_mec_evidence.schedule_verification_due_on
            expect(non_esi_mec_evidence.verification_outstanding).to be_truthy
            expect(non_esi_mec_evidence.is_satisfied).to be_falsey
            expect(non_esi_mec_evidence.state_histories.last.from_state).to eq :negative_response_received
            expect(non_esi_mec_evidence.state_histories.last.to_state).to eq :outstanding
          end

          it "should not update primary local mec evidence if it is in outstanding" do
            local_mec_evidence = @primary_aptc_csr_eligibility.local_mec_evidence
            expect(local_mec_evidence).to be_outstanding
            expect(local_mec_evidence.state_histories.present?).to be_falsey
          end

          it "should not update dependent income_evidence to outstanding state" do
            income_evidence = @dependent_aptc_csr_eligibility.income_evidence
            expect(income_evidence).to be_pending
            expect(income_evidence.state_histories.present?).to be_falsey
          end

          it "should not update dependent esi_mec_evidence to outstanding state" do
            esi_mec_evidence = @dependent_aptc_csr_eligibility.esi_mec_evidence
            expect(esi_mec_evidence.current_state).to eq :verified
            expect(esi_mec_evidence.state_histories.present?).to be_falsey
          end

          it "should not update dependent non_esi_mec_evidence to outstanding state" do
            non_esi_mec_evidence = @dependent_aptc_csr_eligibility.non_esi_mec_evidence
            expect(non_esi_mec_evidence).to be_negative_response_received
            expect(non_esi_mec_evidence.due_on).to be_nil
            expect(non_esi_mec_evidence.verification_outstanding).to be_falsey
            expect(non_esi_mec_evidence.is_satisfied).to be_truthy
            expect(non_esi_mec_evidence.state_histories.present?).to be_falsey
          end

          it "should not update dependent local mec evidence if it is in outstanding" do
            local_mec_evidence = @dependent_aptc_csr_eligibility.local_mec_evidence
            expect(local_mec_evidence).to be_outstanding
            expect(local_mec_evidence.due_on).not_to be_nil
            expect(local_mec_evidence.verification_outstanding).to be_truthy
            expect(local_mec_evidence.is_satisfied).to be_falsey
            expect(local_mec_evidence.state_histories.present?).to be_falsey
          end
        end

        context "for individual market eligibility" do
          it "should not move dependent citizenship evidence from rejected" do
            citizenship_evidence = @dependent_individual_market_eligibility.citizenship_evidence
            expect(citizenship_evidence).to be_rejected
            expect(citizenship_evidence.due_on).to eq(Date.today + 5.days)
            expect(citizenship_evidence.verification_outstanding).to be_truthy
            expect(citizenship_evidence.is_satisfied).to be_falsey
          end

          it "should not move dependent social security evidence to outstanding state" do
            social_security_evidence = @dependent_individual_market_eligibility.social_security_number_evidence
            expect(social_security_evidence).to be_pending
            expect(social_security_evidence.due_on).to be_nil
            expect(social_security_evidence.verification_outstanding).to be_falsey
            expect(social_security_evidence.is_satisfied).to be_truthy
            expect(social_security_evidence.state_histories.present?).to be_falsey
          end

          it "should update dependent american_indian_evidence state" do
            american_indian_evidence = @dependent_individual_market_eligibility.american_indian_evidence
            expect(american_indian_evidence).to be_negative_response_received
            expect(american_indian_evidence.state_histories.present?).to be_truthy
            expect(american_indian_evidence.state_histories.last.from_state).to eq :outstanding
            expect(american_indian_evidence.state_histories.last.to_state).to eq :negative_response_received
          end
        end
      end
    end
  end
end