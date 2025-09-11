# frozen_string_literal: true

require 'rails_helper'
require "#{FinancialAssistance::Engine.root}/spec/shared_examples/ifsv/test_ifsv_eligibility_response"

RSpec.describe ::FinancialAssistance::Operations::Applications::Ifsv::H9t::IfsvEligibilityDetermination, dbclean: :after_each do
  include_context 'FDSH IFSV sample response'

  before :all do
    DatabaseCleaner.clean
  end

  context "when qhp feature is disabled" do
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true, first_name: "main_name", hbx_id: "1629165429385938") }

    let!(:application) do
      FactoryBot.create(:financial_assistance_application, hbx_id: '200000126', aasm_state: "determined", family_id: family.id)
    end

    let!(:ed) do
      eli_d = FactoryBot.create(:financial_assistance_eligibility_determination, application: application)
      eli_d.update_attributes!(hbx_assigned_id: '12345')
      eli_d
    end

    let!(:applicant) do
      FactoryBot.create(:financial_assistance_applicant,
                        :with_income_evidence,
                        eligibility_determination_id: ed.id,
                        person_hbx_id: '1629165429385938',
                        is_primary_applicant: true,
                        first_name: 'Income',
                        last_name: 'evidence',
                        ssn: "111111111",
                        dob: Date.new(1988, 11, 11),
                        family_member_id: family.primary_family_member.id,
                        application: application)
    end

    let!(:applicant2) do
      FactoryBot.create(:financial_assistance_applicant,
                        eligibility_determination_id: ed.id,
                        person_hbx_id: '1629165429385939',
                        is_primary_applicant: true,
                        first_name: 'Non Income',
                        last_name: 'evidence',
                        ssn: "222222222",
                        dob: Date.new(1989, 11, 11),
                        application: application)
    end

    let(:enrollment) { nil }

    before do
      allow(subject).to receive(:qhp_application_feature_enabled?).and_return(false)
    end

    context 'success' do
      context 'FTI Ifsv eligible response' do
        let(:payload) { response_payload }
        before do
          enrollment
          @applicant = application.applicants.first
          @result = subject.call({payload: payload, call_type: nil})

          @application = ::FinancialAssistance::Application.by_hbx_id(payload[:hbx_id]).first.reload
          @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(payload).success
        end

        it 'should return success' do
          expect(@result).to be_success
        end

        it 'should update applicant verification' do
          @applicant.reload
          income_evidence = @applicant.income_evidence
          expect(income_evidence.verified?).to be_truthy
          expect(income_evidence.verification_outstanding).to be_falsey
          expect(income_evidence.due_on).to be_blank
          expect(income_evidence.is_satisfied).to eq true
          expect(income_evidence.request_results.present?).to eq true
          expect(@result.success).to eq('Successfully updated Applicant with evidence')
        end

        context 'when is_ifsv_eligible is true' do
          let(:payload) do
            response_payload[:tax_households].each { |th| th[:is_ifsv_eligible] = true }
            response_payload
          end

          it 'should return success' do
            expect(@result).to be_success
          end

          it 'should return verified status' do
            @applicant.reload
            income_evidence = @applicant.income_evidence
            expect(income_evidence.verified?).to be_truthy
            expect(income_evidence.verification_outstanding).to be_falsey
          end
        end

        context 'when is_ifsv_eligible is false' do
          let(:payload) do
            response_payload[:tax_households].each { |th| th[:is_ifsv_eligible] = false }
            response_payload
          end

          context 'when not enrolled' do

            it 'should return success' do
              expect(@result).to be_success
            end

            it 'should return negative_response_received' do
              @applicant.reload
              income_evidence = @applicant.income_evidence
              expect(income_evidence.negative_response_received?).to be_truthy
              expect(income_evidence.verification_outstanding).to be_falsey
            end
          end

          context 'when enrolled' do
            let(:enrollment) { FactoryBot.create(:hbx_enrollment, :with_enrollment_members, :with_health_product, family: family, enrollment_members: family.family_members) }

            it 'should return success' do
              expect(@result).to be_success
            end

            context 'with aptc used' do

              let(:enrollment) { FactoryBot.create(:hbx_enrollment, :with_aptc_enrollment_members, :with_health_product, family: family, enrollment_members: family.family_members) }

              it 'returns outstanding' do
                subject.call({payload: response_payload, call_type: nil})

                @applicant.reload
                income_evidence = @applicant.income_evidence
                expect(income_evidence.outstanding?).to be_truthy
                expect(income_evidence.verification_outstanding).to be_truthy
              end

              it 'returns review when current status is review' do
                @applicant.income_evidence.update_attributes(aasm_state: 'review')
                subject.call({payload: response_payload, call_type: nil})

                @applicant.reload
                income_evidence = @applicant.income_evidence
                expect(income_evidence.outstanding?).to be_falsey
                expect(income_evidence.aasm_state).to eq 'review'
              end

              it 'returns rejected when current status is rejected' do
                @applicant.income_evidence.update_attributes(aasm_state: 'rejected')
                subject.call({payload: response_payload, call_type: nil})

                @applicant.reload
                income_evidence = @applicant.income_evidence
                expect(income_evidence.outstanding?).to be_falsey
                expect(income_evidence.aasm_state).to eq 'rejected'
              end
            end

            context 'without aptc used' do
              let(:enrollment) { FactoryBot.create(:hbx_enrollment, :with_enrollment_members, :with_health_product, family: family, enrollment_members: family.family_members) }

              it 'returns negative_response_received' do
                enrollment.product.update(csr_variant_id: '01')
                enrollment.reload
                subject.call({payload: response_payload, call_type: nil})

                @applicant.reload
                income_evidence = @applicant.income_evidence
                expect(income_evidence.negative_response_received?).to be_truthy
                expect(income_evidence.verification_outstanding).to be_falsey
              end
            end

            context 'with csr used' do
              let(:enrollment) { FactoryBot.create(:hbx_enrollment, :with_enrollment_members, :with_health_product, family: family, enrollment_members: family.family_members) }

              let!(:applicant) do
                FactoryBot.create(:financial_assistance_applicant,
                                  :with_income_evidence,
                                  csr_eligibility_kind: 'csr_87',
                                  eligibility_determination_id: ed.id,
                                  person_hbx_id: '1629165429385938',
                                  is_primary_applicant: true,
                                  first_name: 'Income',
                                  last_name: 'evidence',
                                  ssn: "111111111",
                                  dob: Date.new(1988, 11, 11),
                                  family_member_id: family.primary_family_member.id,
                                  application: application)
              end

              it 'returns outstanding' do
                subject.call({payload: response_payload, call_type: nil})

                @applicant.reload
                income_evidence = @applicant.income_evidence
                expect(income_evidence.outstanding?).to be_truthy
                expect(income_evidence.verification_outstanding).to be_truthy
              end
            end
          end
        end
      end

      context "applicant without evidence" do
        it 'should log an error if no income evidence present for an applicant' do
          log_message = "Income Evidence Not Found for applicant with person_hbx_id: 1629165429385939 in application with hbx_id: 200000126"
          expect(Rails.logger).to receive(:error).at_least(:once).with(log_message)
          subject.call({payload: response_payload, call_type: nil})
        end
      end

      context 'FTI Ifsv ineligible response' do
        before do
          @applicant = application.applicants.first
          @result = subject.call({payload: response_payload_2, call_type: nil})

          @application = ::FinancialAssistance::Application.by_hbx_id(response_payload_2[:hbx_id]).first.reload
          @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(response_payload_2).success
        end

        it 'should return success' do
          expect(@result).to be_success
        end

        it 'should update applicant verification' do
          @applicant.reload
          income_evidence = @applicant.income_evidence
          expect(income_evidence.outstanding?).to be_falsey
          expect(income_evidence.verification_outstanding).to be_falsey
          expect(income_evidence.negative_response_received?).to be_truthy
          expect(income_evidence.is_satisfied).to eq true
          expect(income_evidence.request_results.present?).to eq true
          expect(@result.success).to eq('Successfully updated Applicant with evidence')
        end
      end

      context 'when Retry with Ifsv ineligible response' do
        let(:income_evidence) { applicant.income_evidence }

        before do
          income_evidence.verification_histories.create(action: "retry")
          income_evidence.save
          subject.call({payload: response_payload_2, call_type: nil})
          income_evidence.reload
        end

        it 'should not update income' do
          expect(income_evidence.pending?).to be_truthy
          expect(income_evidence.due_on).to eq nil
        end

        it 'should record the payload on the retry' do
          expect(income_evidence.request_results.count).to eq 1
        end
      end
    end
  end

  context 'when qhp feature is enabled' do
    let!(:hbx_profile) { FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period) }
    let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
    let(:benefit_coverage_period) { hbx_profile.benefit_sponsorship.benefit_coverage_periods.first }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: found_person) }
    let(:found_person) { FactoryBot.create(:person, :with_ssn, first_name: "main_name", hbx_id: "1629165429385938") }

    let(:application) do
      FactoryBot.create(:application,
                        family_id: family.id,
                        hbx_id: '200000126',
                        aasm_state: "determined",
                        effective_date: (TimeKeeper.date_of_record - 12.days),
                        origin: :user,
                        assistance_year: TimeKeeper.date_of_record.year,
                        generation_reason: :manual,
                        renewal_base_year: TimeKeeper.date_of_record.year + 1)
    end

    let(:applicant) do
      FactoryBot.create(:applicant,
                        first_name: found_person.first_name,
                        last_name: found_person.last_name,
                        application: application,
                        dob: found_person.dob,
                        encrypted_ssn: found_person.encrypted_ssn,
                        is_primary_applicant: true,
                        family_member_id: family.family_members[0].id,
                        person_hbx_id: found_person.hbx_id,
                        addresses: [FactoryBot.build(:financial_assistance_address)])
    end

    let(:dependent_person) { FactoryBot.create(:person, :with_ssn, hbx_id: "1629165429385939") }
    let(:dependent_family_member) { FactoryBot.create(:family_member, family: family, person: dependent_person) }
    let(:dependent_applicant) do
      FactoryBot.create(:applicant,
                        first_name: dependent_person.first_name,
                        last_name: dependent_person.last_name,
                        ssn: dependent_person.ssn,
                        application: application,
                        dob: TimeKeeper.date_of_record - 40.years,
                        is_primary_applicant: false,
                        family_member_id: dependent_family_member.id,
                        person_hbx_id: dependent_person.hbx_id,
                        addresses: [FactoryBot.build(:financial_assistance_address)])
    end

    let!(:relationships) do
      application.add_relationship(applicant, dependent_applicant, 'spouse')
    end
    let!(:build_eligibilities) do
      update_benchmark_premiums
      application.save!
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

    let(:income_evidence) do
      FactoryBot.create(:income_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::IncomeEvidence',key: :income_evidence, title: 'Income Evidence', determined_at: TimeKeeper.date_of_record,
                                          description: 'Income Evidence Description', current_state: "pending")
    end

    let(:create_embed_docs) do
      build_eligibilities
      [income_evidence].each do |evidence|
        FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 2.days.ago)
        FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 1.day.ago)
        FactoryBot.create(:v3_verification_history, evidence: evidence)
        evidence.documents.create(title: 'document.pdf', creator: 'mehl', subject: 'document.pdf', publisher: 'mehl', type: 'text', identifier: 'identifier', source: 'enroll_system', language: 'en')
      end
    end

    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      allow(::Operations::Eligibilities::BuildFamilyDetermination).to receive(:new).and_return(double(call: Dry::Monads::Success(true)))
    end

    context 'FTI Ifsv eligible response' do
      context 'when is_ifsv_eligible is true' do
        let(:payload) do
          response_payload[:tax_households].each { |th| th[:is_ifsv_eligible] = true }
          response_payload
        end

        before do
          create_embed_docs
          @applicant = application.applicants.first
          application.applicants[0].update_attributes(person_hbx_id: family.primary_person.hbx_id)
          application.applicants[1].update_attributes(person_hbx_id: dependent_person.hbx_id)
          @result = subject.call({payload: payload, call_type: "hub_call"})

          @application = ::FinancialAssistance::Application.by_hbx_id(payload[:hbx_id]).first
          @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(payload).success
        end

        it 'should return success' do
          expect(@result).to be_success
        end

        it 'should return verified status' do
          @applicant.reload
          income_evidence = @applicant.aptc_csr_eligibility.income_evidence
          expect(income_evidence.verified?).to be_truthy
          expect(income_evidence.verification_outstanding).to be_falsey
        end
      end

      context 'when is_ifsv_eligible is false' do
        let(:payload) do
          response_payload[:tax_households].each { |th| th[:is_ifsv_eligible] = false }
          response_payload
        end

        before do
          create_embed_docs
          @applicant = application.applicants.first
          application.applicants[0].update_attributes(person_hbx_id: family.primary_person.hbx_id)
          application.applicants[1].update_attributes(person_hbx_id: dependent_person.hbx_id)
          @result = subject.call(payload: payload)

          @application = ::FinancialAssistance::Application.by_hbx_id(payload[:hbx_id]).first
          @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(payload).success
        end

        context 'when not enrolled' do
          it 'should return success' do
            expect(@result).to be_success
          end

          it 'should return negative_response_received' do
            @applicant.reload
            income_evidence = @applicant.aptc_csr_eligibility.income_evidence
            expect(income_evidence.negative_response_received?).to be_truthy
            expect(income_evidence.verification_outstanding).to be_falsey
          end
        end

        context 'when enrolled' do
          let!(:enrollment) { FactoryBot.create(:hbx_enrollment, :with_aptc_enrollment_members, :with_health_product, family: family, enrollment_members: family.family_members) }

          context 'with aptc used' do
            before do
              enrollment.update_attributes(applied_aptc_amount: 200)
            end

            let(:payload) do
              response_payload[:tax_households].each { |th| th[:is_ifsv_eligible] = false }
              response_payload
            end

            it 'returns outstanding' do
              subject.call({payload: response_payload, call_type: "hub_call"})
              @applicant.reload
              income_evidence = @applicant.aptc_csr_eligibility.income_evidence
              expect(income_evidence.current_state).to eq :outstanding
              expect(income_evidence.verification_outstanding).to be_truthy
              expect(income_evidence.is_satisfied).to be_falsey
            end
          end

          context 'without aptc used' do
            it 'returns outstanding' do
              enrollment.product.update(csr_variant_id: '01')
              enrollment.reload
              subject.call({payload: response_payload, call_type: "hub_call"})

              @applicant.reload
              income_evidence = @applicant.aptc_csr_eligibility.income_evidence
              expect(income_evidence.current_state).to eq :negative_response_received
              expect(income_evidence.verification_outstanding).to be_falsey
              expect(income_evidence.due_on).not_to be_present
            end
          end

          context 'with csr used' do
            it 'returns outstanding' do
              enrollment.product.update(csr_variant_id: '02')
              enrollment.reload
              subject.call({payload: response_payload, call_type: "hub_call"})

              @applicant.reload
              income_evidence = @applicant.aptc_csr_eligibility.income_evidence
              expect(income_evidence.current_state).to eq :outstanding
              expect(income_evidence.verification_outstanding).to be_truthy
              expect(income_evidence.due_on).to be_present
            end
          end
        end
      end
    end

  end
end

def update_benchmark_premiums
  ::FinancialAssistance::Application.each do |app|
    applicant_hbx_ids = app.applicants.pluck(:person_hbx_id)
    member_premiums = applicant_hbx_ids.collect do |applicant_hbx_id|
      { member_identifier: applicant_hbx_id, monthly_premium: 90.0 }
    end.compact
    premiums_info = { health_only_lcsp_premiums: member_premiums, health_only_slcsp_premiums: member_premiums }
    app.applicants.each { |applicant| applicant.benchmark_premiums = premiums_info }
    app.save!
    app.reload
  end
end
