# frozen_string_literal: true

require 'rails_helper'
require "#{FinancialAssistance::Engine.root}/spec/shared_examples/medicaid_gateway/test_aces_mec_response"

RSpec.describe ::FinancialAssistance::Operations::Applications::MedicaidGateway::AddMecCheckApplication, dbclean: :after_each do

  before :all do
    DatabaseCleaner.clean
  end

  let(:family) { FactoryBot.create(:family, :with_primary_family_member)}

  let!(:application) do
    FactoryBot.create(:financial_assistance_application, hbx_id: '200000126', aasm_state: "determined", family_id: family.id)
  end
  let!(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      eligibility_determination_id: nil,
                      person_hbx_id: '1629165429385938',
                      is_primary_applicant: true,
                      first_name: 'aces',
                      last_name: 'evidence',
                      ssn: "518124854",
                      dob: Date.new(1988, 11, 11),
                      family_member_id: family.primary_family_member.id,
                      application: application)
  end

  let(:enrollment) { nil }

  before do
    allow(subject).to receive(:qhp_application_feature_enabled?).and_return(false)
  end

  context 'success' do
    context 'ACES MEC Check' do
      include_context 'ACES MEC Check sample response'

      let(:payload) { response_payload }
      let(:due_on) { nil }
      let(:aasm_state) { 'attested' }

      before do
        enrollment
        @applicant = application.applicants.first
        @applicant.build_local_mec_evidence(key: :local_mec, title: "Local MEC", aasm_state: aasm_state,
                                            due_on: due_on)
        @applicant.save
        @result = subject.call({payload: payload})

        @application = ::FinancialAssistance::Application.by_hbx_id(payload[:hbx_id]).first.reload
        @app_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(payload).success
      end

      it 'should return success' do
        expect(@result).to be_success
      end

      it 'should update applicant verification' do
        @applicant.reload
        expect(@applicant.local_mec_evidence.is_satisfied).to be_truthy
        expect(@applicant.local_mec_evidence.due_on).to be_nil
        expect(@applicant.local_mec_evidence.request_results.present?).to eq true
        expect(@result.success).to eq('Successfully updated Applicant with evidences and verifications')
      end

      context 'when aasm_state is verified' do
        let(:payload) do
          response_payload[:applicants].each { |applicant| applicant[:local_mec_evidence][:aasm_state] = 'verified' }
          response_payload
        end

        it 'should return success' do
          expect(@result).to be_success
        end

        it 'should update applicant verification' do
          @applicant.reload
          expect(@applicant.local_mec_evidence.aasm_state).to eq "attested"
          expect(@applicant.local_mec_evidence.request_results.present?).to eq true
          expect(@result.success).to eq('Successfully updated Applicant with evidences and verifications')
        end
      end

      context 'when aasm_state is outstanding' do
        let(:payload) do
          response_payload[:applicants].each { |applicant| applicant[:local_mec_evidence][:aasm_state] = 'outstanding' }
          response_payload
        end

        context 'when not enrolled' do

          it 'should return success' do
            expect(@result).to be_success
          end

          it 'should update applicant verification' do
            @applicant.reload
            expect(@applicant.local_mec_evidence.aasm_state).to eq "negative_response_received"
            expect(@applicant.local_mec_evidence.request_results.present?).to eq true
            expect(@result.success).to eq('Successfully updated Applicant with evidences and verifications')
          end
        end

        context 'Bulk Local Mec call and not enrolled' do
          let(:request_result_hash) do
            {
              :result => "eligible",
              :source => "MEDC",
              :code => "7313",
              :code_description => "Applicant Not Found",
              :action => 'Bulk Call'
            }
          end


          it 'should return success' do
            expect(@result).to be_success
          end

          it 'should not set due_on on local mec evidence' do
            @applicant.reload
            expect(@applicant.local_mec_evidence.aasm_state).to eq "negative_response_received"
            expect(@applicant.local_mec_evidence.due_on).to eq nil
          end
        end

        context 'Bulk Local Mec call, enrolled and due date already exists on evidence' do
          let(:enrollment) { FactoryBot.create(:hbx_enrollment, :with_enrollment_members, :with_health_product, family: family, enrollment_members: family.family_members, effective_on: Date.new(application.assistance_year)) }
          let(:due_on) { TimeKeeper.date_of_record }
          let(:aasm_state) { 'outstanding' }

          it 'should return success' do
            expect(@result).to be_success
          end

          it 'should not update due_on on local mec evidence' do
            @applicant.reload
            expect(@applicant.local_mec_evidence.aasm_state).to eq "outstanding"
            expect(@applicant.local_mec_evidence.due_on).to eq TimeKeeper.date_of_record
          end
        end

        context 'when enrolled' do
          let(:enrollment) { FactoryBot.create(:hbx_enrollment, :with_enrollment_members, :with_health_product, family: family, enrollment_members: family.family_members, effective_on: Date.new(application.assistance_year)) }

          it 'should return success' do
            expect(@result).to be_success
          end

          it 'should update applicant verification' do
            @applicant.reload
            expect(@applicant.local_mec_evidence.aasm_state).to eq "outstanding"
            expect(@applicant.local_mec_evidence.request_results.present?).to eq true
            expect(@applicant.local_mec_evidence.due_on).not_to eq nil
            expect(@result.success).to eq('Successfully updated Applicant with evidences and verifications')
          end
        end

        context "when an enrollment with a renewal status exists" do
          let(:enrollment) do
            FactoryBot.create(
              :hbx_enrollment,
              :with_enrollment_members,
              :with_health_product,
              family: family,
              enrollment_members: family.family_members,
              effective_on: Date.new(application.assistance_year),
              aasm_state: 'auto_renewing'
            )
          end

          it 'should return success' do
            expect(@result).to be_success
          end

          it 'should update applicant verification' do
            @applicant.reload
            expect(@applicant.local_mec_evidence.aasm_state).to eq "outstanding"
            expect(@applicant.local_mec_evidence.request_results.present?).to eq true
            expect(@applicant.local_mec_evidence.due_on).not_to eq nil
            expect(@result.success).to eq('Successfully updated Applicant with evidences and verifications')
          end
        end

        context "when an enrollment with a renewal status exists with a different effective on date than the application year" do
          let(:enrollment) do
            FactoryBot.create(
              :hbx_enrollment,
              :with_enrollment_members,
              :with_health_product,
              family: family,
              enrollment_members: family.family_members,
              effective_on: Date.new(application.assistance_year + 1),
              aasm_state: 'auto_renewing'
            )
          end

          it 'should return success' do
            expect(@result).to be_success
          end

          it 'should update applicant verification' do
            @applicant.reload
            expect(@applicant.local_mec_evidence.aasm_state).to eq "negative_response_received"
            expect(@applicant.local_mec_evidence.request_results.present?).to eq true
            expect(@applicant.local_mec_evidence.due_on).to eq nil
            expect(@result.success).to eq('Successfully updated Applicant with evidences and verifications')
          end
        end

        context "Bulk Local Mec call and enrolled" do
          let(:enrollment) { FactoryBot.create(:hbx_enrollment, :with_enrollment_members, :with_health_product, family: family, enrollment_members: family.family_members, effective_on: Date.new(application.assistance_year)) }
          let(:request_result_hash) do
            {
              :result => "eligible",
              :source => "MEDC",
              :code => "7313",
              :code_description => "Applicant Not Found",
              :action => 'Bulk Call'
            }
          end

          it 'should return success' do
            expect(@result).to be_success
          end

          it 'should set due_on on local mec evidence' do
            due_date = TimeKeeper.date_of_record + EnrollRegistry[:bulk_call_verification_due_in_days].item.to_i
            @applicant.reload
            expect(@applicant.local_mec_evidence.aasm_state).to eq "outstanding"
            expect(@applicant.local_mec_evidence.due_on).to eq due_date
          end
        end

        context 'Negative Response Received logic update' do
          RSpec.shared_examples_for "enrollment with csr_variant_id" do |csr_variant_id, is_aptc_zero, expected_evidence_status|
            let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, csr_variant_id: csr_variant_id)}
            let(:enrollment) do
              FactoryBot.create(
                :hbx_enrollment,
                :with_enrollment_members,
                family: family,
                enrollment_members: family.family_members,
                product: product,
                effective_on: Date.new(application.assistance_year),
                applied_aptc_amount: is_aptc_zero ? 0.00 : 100.00
              )
            end

            before :each do
              @result = subject.call({payload: payload})
            end
            it 'should return success' do
              expect(@result).to be_success
            end

            it 'should set the aasm_state on local mec evidence to outstanding when csr is income based and has aptc' do
              expect(@applicant.reload.local_mec_evidence.aasm_state).to eq expected_evidence_status
            end
          end

          it_behaves_like "enrollment with csr_variant_id", "01", false, "outstanding"
          it_behaves_like "enrollment with csr_variant_id", "01", true, "negative_response_received"
          it_behaves_like "enrollment with csr_variant_id", "02", true, "outstanding"
          it_behaves_like "enrollment with csr_variant_id", "03", false, "outstanding"
          it_behaves_like "enrollment with csr_variant_id", "03", true, "negative_response_received"
          it_behaves_like "enrollment with csr_variant_id", "04", true, "outstanding"
          it_behaves_like "enrollment with csr_variant_id", "05", true, "outstanding"
          it_behaves_like "enrollment with csr_variant_id", "06", true, "outstanding"
        end
      end

      context 'when qhp application feature is enabled' do
        before do
          allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:mec_check).and_return(true)
          allow(subject).to receive(:qhp_application_feature_enabled?).and_return(true)
          allow(::Operations::Eligibilities::BuildFamilyDetermination).to receive(:new).and_return(double(call: Dry::Monads::Success(true)))
          enrollment
          @applicant = application.applicants.first
          @applicant.build_aptc_eligibilities_evidences
          @applicant.save
          @result = subject.call({payload: payload, call_type: 'application_determination'})
        end

        it 'should return success' do
          expect(@result).to be_success
        end

        context 'when aasm_state is verified' do
          let(:payload) do
            response_payload[:applicants].each { |applicant| applicant[:local_mec_evidence][:aasm_state] = 'verified' }
            response_payload
          end

          it 'should return success' do
            expect(@result).to be_success
          end

          it 'should update applicant verification' do
            @applicant.reload
            local_mec = @applicant.aptc_csr_eligibility&.local_mec_evidence
            expect(local_mec.current_state).to eq :attested
            expect(local_mec.request_results.present?).to eq true
            expect(@result.success).to eq('Successfully updated Applicant with evidences and verifications')
          end
        end

        context 'when aasm_state is outstanding' do
          let(:payload) do
            response_payload[:applicants].each { |applicant| applicant[:local_mec_evidence][:aasm_state] = 'outstanding' }
            response_payload
          end

          it 'should return success' do
            expect(@result).to be_success
          end
        end
      end
    end
  end
end
